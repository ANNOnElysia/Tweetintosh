//
//  Models.swift
//  Tweetintosh - Headless Data-driven Client
//

import Foundation

struct TweetVideoVariant: Codable, Hashable {
    var contentType: String
    var url: String
    var bitrate: Int?
    
    private static let sizePattern = try! NSRegularExpression(pattern: #"/(\d{2,4})x(\d{2,4})/"#)
    
    // Quality as "p" (the shorter side, so portrait 720x1280 is 720p), read from X's URL (".../vid/avc1/1280x720/...")
    var qualityHeight: Int? {
        let range = NSRange(url.startIndex..., in: url)
        guard let match = Self.sizePattern.firstMatch(in: url, range: range),
              let w = Range(match.range(at: 1), in: url).flatMap({ Int(url[$0]) }),
              let h = Range(match.range(at: 2), in: url).flatMap({ Int(url[$0]) }) else { return nil }
        return min(w, h)
    }
}

struct TweetVideoInfo: Codable, Hashable {
    var durationMillis: Int?
    var aspectRatio: [Int]?
    var variants: [TweetVideoVariant]
    
    var highestBitrateVariant: TweetVideoVariant? {
        variants
            .filter { $0.contentType == "video/mp4" && ($0.bitrate ?? 0) > 0 }
            .max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
            ?? variants.first(where: { $0.contentType == "video/mp4" })
    }
    
    var hlsVariant: TweetVideoVariant? {
        variants.first { $0.contentType == "application/x-mpegURL" }
    }
    
    var sortedMp4Variants: [TweetVideoVariant] {
        variants
            .filter { $0.contentType == "video/mp4" }
            .sorted(by: { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) })
    }
    
    // The distinct MP4 resolutions this video is offered in, best first
    var availableHeights: [Int] {
        Array(Set(sortedMp4Variants.compactMap { $0.qualityHeight })).sorted(by: >)
    }
    
    // The best MP4 at a given resolution
    func mp4Variant(height: Int) -> TweetVideoVariant? {
        sortedMp4Variants.first { $0.qualityHeight == height }
    }
    
    var durationSeconds: Double {
        Double(durationMillis ?? 0) / 1000.0
    }
    
    var formattedDuration: String {
        guard let ms = durationMillis, ms > 0 else { return "" }
        let totalSecs = ms / 1000
        let m = totalSecs / 60
        let s = totalSecs % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct TweetMedia: Codable, Hashable, Identifiable {
    var id: String
    var type: String // photo, video, animated_gif
    var mediaUrl: String
    var previewUrl: String?
    var width: Int
    var height: Int
    var videoInfo: TweetVideoInfo?
    
    var isVideo: Bool {
        return type == "video" || type == "animated_gif" || videoInfo != nil
    }
    
    var aspectRatio: CGFloat {
        if let ar = videoInfo?.aspectRatio, ar.count >= 2, ar[1] > 0 {
            return CGFloat(ar[0]) / CGFloat(ar[1])
        }
        guard height > 0 else { return 1.77 }
        return CGFloat(width) / CGFloat(height)
    }
}

struct TweetUser: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var screenName: String
    var avatarUrl: String?
    var isVerified: Bool
    // Profile details for the deep-press profile peek (optional: older caches and some payloads lack them)
    var bio: String? = nil
    var followersCount: Int? = nil
    var followingCount: Int? = nil
    var bannerUrl: String? = nil
    var location: String? = nil
    var bioLinks: [TweetLink]? = nil
    // Relationship to the signed-in account. blockedBy: this user blocked you (you can still read their posts
    // but can't like, repost, bookmark, reply, or follow); blocking: you blocked them.
    var blockedBy: Bool? = nil
    var blocking: Bool? = nil

    var formattedHandle: String {
        return "@" + screenName
    }
}

// A URL entity from the tweet text: `url` is the t.co link as it appears in the raw text
struct TweetLink: Codable, Hashable {
    var url: String
    var expandedUrl: String
    var displayUrl: String
}

// A link's position in displayBodyText (UTF-16 offsets, matching NSString / NSRange)
struct DisplayLink: Hashable {
    var location: Int
    var length: Int
    var url: String
}

final class QuotedTweetBox: Codable, Hashable {
    let tweet: Tweet
    init(tweet: Tweet) { self.tweet = tweet }
    static func == (lhs: QuotedTweetBox, rhs: QuotedTweetBox) -> Bool { lhs.tweet == rhs.tweet }
    func hash(into hasher: inout Hasher) { hasher.combine(tweet) }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.tweet = try container.decode(Tweet.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tweet)
    }
}

// The preview of an X Article attached to a post (the full text is fetched when it is opened)
struct TweetArticle: Codable, Hashable {
    var id: String
    var title: String
    var previewText: String
    var coverUrl: String?
}

struct Tweet: Codable, Hashable, Identifiable {
    var id: String
    var text: String
    var createdAt: Date
    var author: TweetUser
    var media: [TweetMedia]
    
    var replyCount: Int
    var retweetCount: Int
    var favoriteCount: Int
    
    var isRetweet: Bool
    var retweetedBy: String?
    
    var isFavorited: Bool = false
    var isRetweeted: Bool = false
    var isBookmarked: Bool = false
    var bookmarkCount: Int = 0
    var viewCount: Int? = nil
    var quotedTweet: QuotedTweetBox? = nil
    var inReplyToScreenName: String? = nil
    var inReplyToStatusId: String? = nil
    var isPromoted: Bool = false
    var links: [TweetLink] = []
    var article: TweetArticle? = nil
    // For a repost, the id of the post it reposts: X gives the repost an id of its own, while the post's page and every
    // other listing of it use the original's
    var originalId: String? = nil
    // A long post's whole text and its links. X sends long posts (past 280 characters, counting CJK twice) cut short in
    // the usual text field, and in full only here.
    private(set) var longText: String? = nil
    private(set) var longLinks: [TweetLink] = []
    // Whether the long text is shown in place of the shortened one. A view state, so never saved.
    private(set) var isTextExpanded = false
    // The post this row stands for, which is what likes, reposts and bookmarks change. Screens match on this, so a repost on
    // Home and the post's own page count as the same post.
    var canonicalId: String { originalId ?? id }
    var quoted: Tweet? {
        quotedTweet?.tweet
    }
    
    // The post links to an X Article (whether or not X sent the article's preview along with it)
    var linksToArticle: Bool {
        article != nil || links.contains { $0.expandedUrl.contains("/i/article/") }
    }
    
    // Cached precomputed strings for zero-cost 120Hz scrolling. Display text is whichever of the short and the long
    // text is showing.
    var displayBodyText: String = ""
    var replyContextText: String? = nil
    var displayLinks: [DisplayLink] = []
    var cleanText: String { displayBodyText }
    struct BodyText: Hashable {
        var text: String
        var links: [DisplayLink]
    }
    private var shortBody = BodyText(text: "", links: [])
    private var longBody: BodyText? = nil
    
    mutating func setLongText(_ text: String, links: [TweetLink]) {
        longText = text
        longLinks = links
        computeParsedTexts()
    }
    
    /// Whether X cut this post's text short, so there is more to show
    var hasLongText: Bool { longBody != nil }
    
    /// Shows the whole text of a long post, or its shortened text again
    mutating func setTextExpanded(_ expanded: Bool) {
        guard let long = longBody, expanded != isTextExpanded else { return }
        isTextExpanded = expanded
        let body = expanded ? long : shortBody
        displayBodyText = body.text
        displayLinks = body.links
    }
    
    /// The same post with its whole text showing, as a post's own page shows it
    var withFullText: Tweet {
        var copy = self
        copy.setTextExpanded(true)
        return copy
    }
    
    /// The post's words as written, in full, with links in full rather than shortened for display, for copying
    var copyableText: String {
        let body = longBody ?? shortBody
        var text = body.text as NSString
        for link in body.links.reversed() {
            text = text.replacingCharacters(in: NSRange(location: link.location, length: link.length), with: link.url) as NSString
        }
        return text as String
    }
    
    private static let mmmDDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    // X sends tweet text with &amp; &lt; &gt; escaped (and occasionally quotes); show the real characters
    private static func unescapeHTML(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")  // last, so "&amp;lt;" stays "&lt;"
    }
    
    private static let leadingMentionRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(@[A-Za-z0-9_]{1,50})\s*"#)
    }()
    
    private static let trailingTCoRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?:https?:\/\/t\.co\/[A-Za-z0-9]+|https?:\/\/[^\s]+)\s*$"#)
    }()
    
    enum CodingKeys: String, CodingKey {
        case id, text, createdAt, author, media
        case replyCount, retweetCount, favoriteCount
        case isRetweet, retweetedBy
        case isFavorited, isRetweeted, isBookmarked, bookmarkCount, viewCount
        case quotedTweet
        case inReplyToScreenName, inReplyToStatusId
        case isPromoted
        case links
        case article
        case originalId
        case longText, longLinks
    }
    
    init(
        id: String,
        text: String,
        createdAt: Date,
        author: TweetUser,
        media: [TweetMedia],
        replyCount: Int,
        retweetCount: Int,
        favoriteCount: Int,
        isRetweet: Bool,
        retweetedBy: String?,
        isFavorited: Bool = false,
        isRetweeted: Bool = false,
        isBookmarked: Bool = false,
        bookmarkCount: Int = 0,
        viewCount: Int? = nil,
        quotedTweet: QuotedTweetBox? = nil,
        inReplyToScreenName: String? = nil,
        inReplyToStatusId: String? = nil,
        isPromoted: Bool = false,
        links: [TweetLink] = [],
        article: TweetArticle? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.author = author
        self.media = media
        self.replyCount = replyCount
        self.retweetCount = retweetCount
        self.favoriteCount = favoriteCount
        self.isRetweet = isRetweet
        self.retweetedBy = retweetedBy
        self.isFavorited = isFavorited
        self.isRetweeted = isRetweeted
        self.isBookmarked = isBookmarked
        self.bookmarkCount = bookmarkCount
        self.viewCount = viewCount
        self.quotedTweet = quotedTweet
        self.inReplyToScreenName = inReplyToScreenName
        self.inReplyToStatusId = inReplyToStatusId
        self.isPromoted = isPromoted
        self.links = links
        self.article = article
        computeParsedTexts()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        author = try container.decode(TweetUser.self, forKey: .author)
        media = try container.decode([TweetMedia].self, forKey: .media)
        replyCount = try container.decode(Int.self, forKey: .replyCount)
        retweetCount = try container.decode(Int.self, forKey: .retweetCount)
        favoriteCount = try container.decode(Int.self, forKey: .favoriteCount)
        isRetweet = try container.decode(Bool.self, forKey: .isRetweet)
        retweetedBy = try container.decodeIfPresent(String.self, forKey: .retweetedBy)
        isFavorited = try container.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
        isRetweeted = try container.decodeIfPresent(Bool.self, forKey: .isRetweeted) ?? false
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        bookmarkCount = try container.decodeIfPresent(Int.self, forKey: .bookmarkCount) ?? 0
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
        quotedTweet = try container.decodeIfPresent(QuotedTweetBox.self, forKey: .quotedTweet)
        inReplyToScreenName = try container.decodeIfPresent(String.self, forKey: .inReplyToScreenName)
        inReplyToStatusId = try container.decodeIfPresent(String.self, forKey: .inReplyToStatusId)
        isPromoted = try container.decodeIfPresent(Bool.self, forKey: .isPromoted) ?? false
        links = try container.decodeIfPresent([TweetLink].self, forKey: .links) ?? []
        article = try container.decodeIfPresent(TweetArticle.self, forKey: .article)
        originalId = try container.decodeIfPresent(String.self, forKey: .originalId)
        longText = try container.decodeIfPresent(String.self, forKey: .longText)
        longLinks = try container.decodeIfPresent([TweetLink].self, forKey: .longLinks) ?? []
        computeParsedTexts()
    }
    
    // Clean text breakdown: strips trailing media t.co URLs and extracts leading reply mentions
    struct TextBreakdown {
        let mentions: [String]
        let body: String
    }
    
    private mutating func computeParsedTexts() {
        let short = Self.parseBody(text, links: links, stripsTrailingLinks: !media.isEmpty || quotedTweet != nil || linksToArticle,
                                   articleLinksToo: linksToArticle)
        var mentions = short.mentions
        // If no leading mentions found in text, but inReplyToScreenName is present
        if mentions.isEmpty, let replyScreenName = inReplyToScreenName, !replyScreenName.isEmpty {
            mentions.append("@" + replyScreenName)
        }
        shortBody = short.body
        // Only a long text that says more than the short one counts; the reply's @mentions are already in the line above
        if let longText = longText {
            let long = Self.parseBody(longText, links: longLinks, stripsTrailingLinks: !media.isEmpty || quotedTweet != nil || linksToArticle,
                                      articleLinksToo: linksToArticle)
            longBody = long.body.text.count > short.body.text.count ? long.body : nil
        } else {
            longBody = nil
        }
        let showing = isTextExpanded ? (longBody ?? shortBody) : shortBody
        self.displayBodyText = showing.text
        self.displayLinks = showing.links
        self.replyContextText = mentions.isEmpty ? nil : LocalizationManager.shared.formatReplyContext(mentions: mentions)
    }
    
    // A post's text made ready to show: HTML entities undone, the media or quote link at its end dropped, leading
    // @mentions taken off (they become the "Replying to" line), and links shown by their display address
    private static func parseBody(_ text: String, links: [TweetLink], stripsTrailingLinks: Bool, articleLinksToo: Bool)
        -> (mentions: [String], body: BodyText) {
        var raw = unescapeHTML(text).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Strip trailing media or quote t.co URLs when media or quote is present
        //    (real link entities stay: they're shown and previewable)
        if stripsTrailingLinks, let tcoRegex = trailingTCoRegex {
            // The link to an attached article is dropped like a media link: the article is shown as a card
            let articleLinks = !articleLinksToo ? [] : links.filter { $0.expandedUrl.contains("/i/article/") }.map { $0.url }
            let linkUrls = Set(links.map { $0.url }).subtracting(articleLinks)
            while true {
                let nsRaw = raw as NSString
                let match = tcoRegex.firstMatch(in: raw, range: NSRange(location: 0, length: nsRaw.length))
                guard let m = match, m.range.location != NSNotFound else { break }
                let matched = nsRaw.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
                if linkUrls.contains(matched) { break }
                raw = nsRaw.substring(to: m.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 2. Extract leading @mentions
        var mentions: [String] = []
        var remainder = raw
        if let regex = leadingMentionRegex {
            while true {
                let nsRemainder = remainder as NSString
                guard let match = regex.firstMatch(in: remainder, range: NSRange(location: 0, length: nsRemainder.length)),
                      match.range.location == 0 else {
                    break
                }
                mentions.append(nsRemainder.substring(with: match.range(at: 1)))
                remainder = nsRemainder.substring(from: match.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 3. Show links by their display URL and record where each one sits for styling and deep-press previews
        var linkRanges: [DisplayLink] = []
        var searchFrom = 0
        for link in links {
            let ns = remainder as NSString
            let found = ns.range(of: link.url, range: NSRange(location: searchFrom, length: ns.length - searchFrom))
            guard found.location != NSNotFound else { continue }
            remainder = ns.replacingCharacters(in: found, with: link.displayUrl)
            let length = (link.displayUrl as NSString).length
            linkRanges.append(DisplayLink(location: found.location, length: length, url: link.expandedUrl))
            searchFrom = found.location + length
        }
        return (mentions, BodyText(text: remainder, links: linkRanges))
    }
    
    var textBreakdown: TextBreakdown {
        TextBreakdown(mentions: [], body: displayBodyText)
    }
    
    var replyMentions: [String] {
        []
    }
    
    // Relative time string helper
    var relativeTime: String {
        let now = Date()
        let interval = now.timeIntervalSince(createdAt)
        
        if interval < 60 {
            return LocalizationManager.shared.t("time_just_now")
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else if interval < 86400 * 7 {
            return "\(Int(interval / 86400))d"
        } else {
            return Self.mmmDDateFormatter.string(from: createdAt)
        }
    }
}

enum HomeFeedType: String, CaseIterable, Identifiable, Codable {
    case forYou = "for_you"
    case following = "following"
    // The posts you have bookmarked on X, newest first
    case bookmarks = "bookmarks"
    case list = "list"
    
    var id: String { rawValue }
    
    var titleKey: String {
        switch self {
        case .forYou: return "feed_for_you"
        case .following: return "feed_following"
        case .bookmarks: return "feed_bookmarks"
        case .list: return "feed_list"
        }
    }
    
    var iconName: String {
        switch self {
        case .forYou: return "sparkles"
        case .following: return "person.2.fill"
        case .bookmarks: return "bookmark.fill"
        case .list: return "list.bullet.rectangle.portrait"
        }
    }
    
    var shortcutKey: String {
        switch self {
        case .forYou: return "⌥Q"
        case .following: return "⌥W"
        case .bookmarks: return "⌥E"
        // Lists have no shortcut: there can be any number of them
        case .list: return ""
        }
    }
    
    var shortcutLetter: String {
        switch self {
        case .forYou: return "Q"
        case .following: return "W"
        case .bookmarks: return "E"
        case .list: return ""
        }
    }
}

struct TwitterList: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var description: String?
    var memberCount: Int
    var subscriberCount: Int
    var isPrivate: Bool
    var isPinned: Bool
    var bannerUrl: String?
    var ownerName: String?
    var ownerHandle: String?
    
    var iconName: String {
        if isPinned {
            return "pin.fill"
        } else if isPrivate {
            return "lock.fill"
        } else {
            return "list.bullet.rectangle.portrait"
        }
    }
}

struct TimelineSnapshot: Codable {
    var tweets: [Tweet]
    var topCursor: String?
    var bottomCursor: String?
    var savedAt: Date
}
