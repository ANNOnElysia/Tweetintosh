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

    // The in-app URL an @mention opens, shared with the AppKit text view that draws a post's body on the timeline
    static func mentionURL(_ name: String) -> URL? {
        URL(string: "\(profileScheme)://profile/\(name)")
    }

    // Whether a link opens inside the app (a profile or a list of people) rather than in the system
    static func isInternal(_ url: URL) -> Bool {
        url.scheme == profileScheme
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
                  let url = mentionURL(String(body[nameRange])) else { continue }
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
            .navigationPointer()
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

// Where the pointer last was over a post's text, shared with the layout without asking SwiftUI to redraw for it
private final class HoverPosition {
    var point: CGPoint?
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
    // The last hover position. The box is what is stored; its point changes on every move without a redraw, and a
    // reflow reads it again.
    @State private var hoverPosition = HoverPosition()
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
                case .active(let point): updateHover(at: point)
                case .ended: updateHover(at: nil)
                }
            }
            // Selectable text is an AppKit text view, which claims the I-beam over its whole frame. Matching that
            // here leaves one answer; a second style for the gaps between lines makes the two ask for the cursor in
            // turn, which is what the pointer flicker was.
            .pointerStyle(pointerStyle)
            // A reused cell, reflowed text or the end of a scroll must not keep an answer about text that has moved,
            // and a pointer resting still gets no new hover event to correct it.
            .onChange(of: currentLayoutKey) { refreshHover() }
            .onChange(of: isEnabled && textLinkPointerEnabled) { refreshHover() }
            .onDisappear { updateHover(at: nil) }
    }

    // A nil point means the pointer left
    private func updateHover(at point: CGPoint?) {
        hoverPosition.point = point
        refreshHover()
    }

    private func refreshHover() {
        // Only the text under the pointer needs an answer; a reflow elsewhere must not lay out a TextKit copy
        guard let point = hoverPosition.point else {
            if isOverLink { isOverLink = false }
            return
        }
        let overLink = currentLayout()?.isLink(at: point) ?? false
        if overLink != isOverLink { isOverLink = overLink }
    }

    private var pointerStyle: PointerStyle? {
        if isOverLink && isEnabled && textLinkPointerEnabled && layoutKey == currentLayoutKey { return .link }
        if selectable && isEnabled { return .horizontalText }
        // The text under the pointer is not a link; an enclosing row may still be clickable, but the hand there
        // would hide the link and never release the pointer when it leaves the link.
        return .default
    }

    private func currentLayout() -> PeekTextLinks.Layout? {
        guard isEnabled && textLinkPointerEnabled, size.width > 0 else { return nil }
        let key = currentLayoutKey
        if let cached = layout, layoutKey == key { return cached }
        let newLayout = PeekTextLinks.Layout(text: tweet.displayBodyText, links: tweet.displayLinks,
                                             fontSize: fontSize, lineSpacing: lineSpacing, width: size.width)
        layout = newLayout
        layoutKey = key
        return newLayout
    }
}
