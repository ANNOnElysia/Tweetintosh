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
        if url.scheme == profileScheme, url.host == "profile" {
            let name = url.lastPathComponent
            NavigationManager.shared.openProfile(TweetUser(id: "", name: name, screenName: name, avatarUrl: nil, isVerified: false))
            return .handled
        }
        return .systemAction(url)
    }
}

extension View {
    // Lets the text inside this view open @mentions as profiles
    func handlesTweetLinks() -> some View {
        environment(\.openURL, OpenURLAction { TweetText.open($0) })
    }
}
