//
//  Models.swift
//  MaX - Headless Data-driven Client
//

import Foundation

struct TweetVideoVariant: Codable, Hashable {
    var contentType: String
    var url: String
    var bitrate: Int?
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
    
    var formattedHandle: String {
        return "@" + screenName
    }
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
    
    enum CodingKeys: String, CodingKey {
        case id, text, createdAt, author, media
        case replyCount, retweetCount, favoriteCount
        case isRetweet, retweetedBy
        case isFavorited, isRetweeted, isBookmarked, bookmarkCount
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
        bookmarkCount: Int = 0
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
    }
    
    // Clean text: strip trailing media t.co links when media is present
    var cleanText: String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !media.isEmpty {
            // Remove trailing https://t.co/xxxxxx URL from the text body (even with whitespace)
            if let range = result.range(of: #"https:\/\/t\.co\/[A-Za-z0-9]+\s*$"#, options: .regularExpression) {
                result.removeSubrange(range)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: createdAt)
        }
    }
}

enum HomeFeedType: String, CaseIterable, Identifiable, Codable {
    case forYou = "for_you"
    case following = "following"
    case list = "list"
    
    var id: String { rawValue }
    
    var titleKey: String {
        switch self {
        case .forYou: return "feed_for_you"
        case .following: return "feed_following"
        case .list: return "feed_list"
        }
    }
    
    var iconName: String {
        switch self {
        case .forYou: return "sparkles"
        case .following: return "person.2.fill"
        case .list: return "list.bullet.rectangle.portrait"
        }
    }
    
    var shortcutKey: String {
        switch self {
        case .forYou: return "⌥Q"
        case .following: return "⌥W"
        case .list: return "⌥E"
        }
    }
    
    var shortcutLetter: String {
        switch self {
        case .forYou: return "Q"
        case .following: return "W"
        case .list: return "E"
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
