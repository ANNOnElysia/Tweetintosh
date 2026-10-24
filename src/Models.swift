//
//  Models.swift
//  MaX - Headless Data-driven Client
//

import Foundation

struct TweetMedia: Codable, Hashable, Identifiable {
    var id: String
    var type: String // photo, video, animated_gif
    var mediaUrl: String
    var previewUrl: String?
    var width: Int
    var height: Int
    
    var aspectRatio: CGFloat {
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
    var iconName: String
    var isCustom: Bool = false
    
    var localizedName: String {
        let loc = LocalizationManager.shared
        switch id {
        case "list_tech": return loc.t("list_tech")
        case "list_dev": return loc.t("list_dev")
        case "list_design": return loc.t("list_design")
        case "list_news": return loc.t("list_news")
        case "list_acg": return loc.t("list_acg")
        default: return name
        }
    }
    
    static let defaultLists: [TwitterList] = [
        TwitterList(id: "list_tech", name: "Tech News", iconName: "cpu"),
        TwitterList(id: "list_dev", name: "Developers", iconName: "chevron.left.forwardslash.chevron.right"),
        TwitterList(id: "list_design", name: "Design & UI", iconName: "paintpalette.fill"),
        TwitterList(id: "list_news", name: "Headlines", iconName: "newspaper.fill"),
        TwitterList(id: "list_acg", name: "ACG & Art", iconName: "sparkles")
    ]
}

struct TimelineSnapshot: Codable {
    var tweets: [Tweet]
    var topCursor: String?
    var bottomCursor: String?
    var savedAt: Date
}
