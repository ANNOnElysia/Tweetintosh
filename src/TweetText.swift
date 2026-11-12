//
//  TweetText.swift
//  Tweetintosh - Headless Data-driven Client
//
//  A post's text with its links and @mentions made clickable. Links open in the browser; a mention opens that
//  account's profile page inside the app.
//

import SwiftUI

enum TweetText {
    private static let profileScheme = "tweetintosh"
    private static let mentionPattern = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_])@([A-Za-z0-9_]{1,15})")

    // A plain post skips the AttributedString: there is nothing in it to style or click
    static func text(_ tweet: Tweet) -> Text {
        let body = tweet.displayBodyText
        if tweet.displayLinks.isEmpty && !body.contains("@") { return Text(verbatim: body) }
        return Text(attributed(tweet))
    }

    static func attributed(_ tweet: Tweet) -> AttributedString {
        let body = tweet.displayBodyText
        var attributed = AttributedString(body)
        var linkRanges: [NSRange] = []

        for link in tweet.displayLinks {
            let nsRange = NSRange(location: link.location, length: link.length)
            guard let range = Range(nsRange, in: body), let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = ThemeManager.accent
            attributed[attrRange].link = URL(string: link.url)
            linkRanges.append(nsRange)
        }

        let whole = NSRange(body.startIndex..., in: body)
        for match in mentionPattern.matches(in: body, range: whole) {
            // Text that is already a link (a URL or an address that merely contains an @) stays as it is
            guard !linkRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let nameRange = Range(match.range(at: 1), in: body),
                  let range = Range(match.range, in: body),
                  let attrRange = Range(range, in: attributed),
                  let url = URL(string: "\(profileScheme)://profile/\(body[nameRange])") else { continue }
            attributed[attrRange].foregroundColor = ThemeManager.accent
            attributed[attrRange].link = url
        }
        return attributed
    }

    // The @mentions in a text, as ranges (in UTF-16 units, like NSRange) with their handles, skipping any that fall
    // inside one of the text's links
    static func mentionRanges(in body: String, excluding links: [DisplayLink]) -> [(range: NSRange, name: String)] {
        let linkRanges = links.map { NSRange(location: $0.location, length: $0.length) }
        let whole = NSRange(body.startIndex..., in: body)
        return mentionPattern.matches(in: body, range: whole).compactMap { match in
            guard !linkRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let nameRange = Range(match.range(at: 1), in: body) else { return nil }
            return (match.range, String(body[nameRange]))
        }
    }

    // What clicking a link in a post does
    static func open(_ url: URL) -> OpenURLAction.Result {
        // A deep press that previewed something must not also activate it when released
        if PeekCoordinator.shared.suppressesActivation { return .handled }
        // tweetintosh://users/<likes|reposts>/<post id>: the people who liked or reposted a post
        if url.scheme == profileScheme, url.host == "users", url.pathComponents.count >= 3,
           let kind = TweetUsersKind(rawValue: url.pathComponents[1]) {
            NavigationManager.shared.openUserList(kind, tweetId: url.pathComponents[2])
            return .handled
        }
        if url.scheme == profileScheme, url.host == "profile" {
            let name = url.lastPathComponent
            NavigationManager.shared.openProfile(TweetUser(id: "", name: name, screenName: name, avatarUrl: nil, isVerified: false))
            return .handled
        }
        return .systemAction(url)
    }
}

/// "Show more" under a long post X cut short, and "Show less" under its whole text, in the accent colour on a line of
/// their own, as X shows them
struct LongTextToggle: View {
    let tweet: Tweet
    var fontSize: CGFloat = 14.5
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if tweet.hasLongText {
            Button {
                TimelineViewModel.shared.setTextExpanded(!tweet.isTextExpanded, for: tweet)
            } label: {
                Text(loc.t(tweet.isTextExpanded ? "show_less" : "show_more"))
                    .font(theme.appFont(size: theme.postSize(fontSize), weight: .medium))
                    .foregroundColor(ThemeManager.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.target)
            .padding(.top, 2)
        }
    }
}

extension View {
    // Lets the text inside this view open @mentions as profiles
    func handlesTweetLinks() -> some View {
        environment(\.openURL, OpenURLAction { TweetText.open($0) })
    }

    // SwiftUI puts a post's links and @mentions inside one Text and offers no pointer style for a run of it, so the
    // hand would otherwise cover the whole post or none of it. The same TextKit hit test the deep-press peek uses
    // says where the pointer is; the layout is built once per width, and only a link or @mention gets the hand.
    func tweetLinkPointer(of tweet: Tweet, fontSize: CGFloat, lineSpacing: CGFloat,
                          selectable: Bool = false) -> some View {
        modifier(TweetLinkPointer(tweet: tweet, fontSize: fontSize, lineSpacing: lineSpacing, selectable: selectable))
    }
}

private struct TextLinkPointerEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var textLinkPointerEnabled: Bool {
        get { self[TextLinkPointerEnabledKey.self] }
        set { self[TextLinkPointerEnabledKey.self] = newValue }
    }
}

private struct TweetLinkPointer: ViewModifier {
    let tweet: Tweet
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let selectable: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.textLinkPointerEnabled) private var textLinkPointerEnabled
    @State private var size: CGSize = .zero
    @State private var isOverLink = false
    @State private var layout: PeekTextLinks.Layout?
    @State private var layoutKey: LayoutKey?

    // Everything the layout's glyph positions depend on
    private struct LayoutKey: Equatable {
        let tweetID: String
        let text: String
        let links: [DisplayLink]
        let size: CGSize
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let fontType: String
        let language: String
    }

    private var currentLayoutKey: LayoutKey {
        LayoutKey(tweetID: tweet.id, text: tweet.displayBodyText, links: tweet.displayLinks, size: size,
                  fontSize: fontSize, lineSpacing: lineSpacing, fontType: ThemeManager.shared.fontType.rawValue,
                  language: LocalizationManager.shared.currentLanguage.rawValue)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let overLink = self.isOverLink(at: point)
                    if overLink != isOverLink { isOverLink = overLink }
                case .ended:
                    if isOverLink { isOverLink = false }
                }
            }
            // A reused cell or a reflow must not reuse the previous text's hover result while the pointer is still.
            // Selectable text names its own I-beam so this layer and AppKit's text view don't fight over the cursor;
            // a plain post leaves the pointer to the row or inherited style.
            .pointerStyle(pointerStyle)
            .onChange(of: currentLayoutKey) { isOverLink = false }
            .onChange(of: isEnabled && textLinkPointerEnabled) { isOverLink = false }
            .onDisappear { isOverLink = false }
    }

    private var pointerStyle: PointerStyle? {
        if isOverLink && isEnabled && textLinkPointerEnabled && layoutKey == currentLayoutKey { return .link }
        return selectable && isEnabled ? .horizontalText : nil
    }

    private func isOverLink(at point: CGPoint) -> Bool {
        guard isEnabled && textLinkPointerEnabled, size.width > 0 else { return false }
        let key = currentLayoutKey
        let layout: PeekTextLinks.Layout
        if let cached = self.layout, layoutKey == key {
            layout = cached
        } else {
            layout = PeekTextLinks.Layout(text: tweet.displayBodyText, links: tweet.displayLinks,
                                          fontSize: fontSize, lineSpacing: lineSpacing, width: size.width)
            self.layout = layout
            layoutKey = key
        }
        return layout.isLink(at: point)
    }
}
