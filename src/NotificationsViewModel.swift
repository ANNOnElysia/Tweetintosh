//
//  NotificationsViewModel.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import Combine

enum NotificationFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case likesAndReposts = 1
    case comments = 2
    case mentions = 3
    
    var id: Int { rawValue }
    
    var titleKey: String {
        switch self {
        case .all: return "notif_filter_all"
        case .likesAndReposts: return "notif_filter_likes_reposts"
        case .comments: return "notif_filter_comments"
        case .mentions: return "notif_filter_mentions"
        }
    }
    
    var iconName: String {
        switch self {
        case .all: return "tray.fill"
        case .likesAndReposts: return "heart.fill"
        case .comments: return "bubble.left.and.bubble.right.fill"
        case .mentions: return "at"
        }
    }
    
    var shortcutKey: String {
        switch self {
        case .all: return "⌥Q"
        case .likesAndReposts: return "⌥W"
        case .comments: return "⌥E"
        case .mentions: return "⌥R"
        }
    }
}

enum NotificationType: String, Codable, Hashable {
    case like
    case retweet
    case reply
    case mention
    case follow
    
    var iconName: String {
        switch self {
        case .like: return "heart.fill"
        case .retweet: return "arrow.2.squarepath"
        case .reply: return "bubble.left.fill"
        case .mention: return "at"
        case .follow: return "person.badge.plus.fill"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .like: return Color(red: 0.95, green: 0.15, blue: 0.45) // Heart Pink
        case .retweet: return Color(red: 0.0, green: 0.73, blue: 0.44) // Retweet Green
        case .reply: return Color(red: 0.11, green: 0.61, blue: 0.94) // Twitter Blue
        case .mention: return Color(red: 0.72, green: 0.38, blue: 0.98) // Purple
        case .follow: return Color(red: 0.0, green: 0.85, blue: 0.85) // Cyan
        }
    }
}

struct NotificationItem: Identifiable, Hashable, Codable {
    var id: String
    var type: NotificationType
    var actors: [TweetUser]
    var actionSummary: String
    var targetTweetSnippet: String?
    var replyBody: String?
    var createdAt: Date
    var iconId: String? = nil
    
    var relativeTime: String {
        let interval = Date().timeIntervalSince(createdAt)
        if interval < 60 {
            return LocalizationManager.shared.t("time_just_now")
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }
    
    var isRecentPost: Bool {
        if iconId == "recommendation_icon" {
            return true
        }
        let lowerSummary = actionSummary.lowercased()
        let matchesRecentPostKeywords = lowerSummary.contains("recent post") ||
            lowerSummary.contains("recent tweet") ||
            lowerSummary.contains("new post") ||
            lowerSummary.contains("new tweet") ||
            lowerSummary.contains("posted a new") ||
            actionSummary.contains("最新帖子") ||
            actionSummary.contains("最新推文") ||
            actionSummary.contains("最新貼文") ||
            actionSummary.contains("发布了新推文") ||
            actionSummary.contains("發布了新貼文") ||
            actionSummary.contains("发布了新帖子") ||
            actionSummary.contains("發布了新帖子") ||
            actionSummary.contains("最新のポスト") ||
            actionSummary.contains("最新の投稿") ||
            actionSummary.contains("新しいポスト") ||
            actionSummary.contains("新しい投稿") ||
            actionSummary.contains("新しいツイート") ||
            actionSummary.contains("최근 게시물") ||
            actionSummary.contains("최근 포스트") ||
            actionSummary.contains("새로운 게시물") ||
            actionSummary.contains("새로운 포스트") ||
            actionSummary.contains("새로운 트윗") ||
            (actionSummary.contains("来自 ") && (actionSummary.contains("帖子") || actionSummary.contains("推文") || actionSummary.contains("最新"))) ||
            (actionSummary.contains("來自 ") && (actionSummary.contains("貼文") || actionSummary.contains("推文") || actionSummary.contains("最新"))) ||
            actionSummary.contains("からの最新") ||
            actionSummary.contains("さんの最新")
        
        return matchesRecentPostKeywords && (type == .mention || iconId == nil)
    }
    
    var localizedActionSummary: String {
        let loc = LocalizationManager.shared
        
        // 1. Determine actor names and others count
        var firstActorName: String = ""
        var secondActorName: String = ""
        var otherCount: Int = 0
        
        if actors.count >= 1 {
            firstActorName = actors[0].name
            if actors.count == 2 {
                secondActorName = actors[1].name
            } else if actors.count > 2 {
                otherCount = actors.count - 1
            }
        }
        
        // If otherCount wasn't inferred from actors list, check if raw actionSummary has "and N others" or "等 N 人" etc.
        if otherCount == 0 && !actionSummary.isEmpty {
            if let regex = try? NSRegularExpression(pattern: #"(?:and|等|他|외)\s*(\d+)"#, options: .caseInsensitive),
               let match = regex.firstMatch(in: actionSummary, range: NSRange(actionSummary.startIndex..., in: actionSummary)),
               let range = Range(match.range(at: 1), in: actionSummary),
               let n = Int(actionSummary[range]) {
                otherCount = n
            }
        }
        
        // If actors list was completely empty, fallback by extracting from actionSummary
        if firstActorName.isEmpty && !actionSummary.isEmpty {
            firstActorName = actionSummary
                .replacingOccurrences(of: " liked your post", with: "")
                .replacingOccurrences(of: " followed you", with: "")
                .replacingOccurrences(of: " reposted your post", with: "")
                .replacingOccurrences(of: " retweeted your post", with: "")
                .replacingOccurrences(of: " replied to your post", with: "")
                .replacingOccurrences(of: " mentioned you in a post", with: "")
                .replacingOccurrences(of: "Recent post from ", with: "")
                .replacingOccurrences(of: " 赞了你的推文", with: "")
                .replacingOccurrences(of: " 关注了你", with: "")
                .replacingOccurrences(of: " 转发了你的推文", with: "")
                .replacingOccurrences(of: " 回复了你的推文", with: "")
                .replacingOccurrences(of: "来自 ", with: "")
                .replacingOccurrences(of: "來自 ", with: "")
                .replacingOccurrences(of: " 的最新帖子", with: "")
                .replacingOccurrences(of: " 的最新推文", with: "")
                .replacingOccurrences(of: " 的最新貼文", with: "")
                .replacingOccurrences(of: "さんからの最新のポスト", with: "")
                .replacingOccurrences(of: "さんの最新のポスト", with: "")
                .replacingOccurrences(of: "からの最新のポスト", with: "")
                .replacingOccurrences(of: "の最新のポスト", with: "")
                .replacingOccurrences(of: "さんの最新の投稿", with: "")
                .replacingOccurrences(of: "さんの最新", with: "")
                .replacingOccurrences(of: "さんの新しい投稿", with: "")
                .replacingOccurrences(of: "님의 최근 게시물", with: "")
                .replacingOccurrences(of: "님의 최근 포스트", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard !firstActorName.isEmpty else {
            return actionSummary
        }
        
        // 2. Detect recent post notification
        if isRecentPost {
            return loc.format("notif_recent_post", ["actor": firstActorName])
        }
        
        let prefix: String
        switch type {
        case .like:
            prefix = "notif_liked"
        case .follow:
            prefix = "notif_followed"
        case .retweet:
            prefix = "notif_reposted"
        case .reply:
            prefix = "notif_replied"
        case .mention:
            return loc.format("notif_mentioned_single", ["actor": firstActorName])
        }
        
        if otherCount > 0 {
            return loc.format("\(prefix)_many", ["actor": firstActorName, "count": "\(otherCount)"])
        } else if !secondActorName.isEmpty {
            return loc.format("\(prefix)_two", ["actor1": firstActorName, "actor2": secondActorName])
        } else {
            return loc.format("\(prefix)_single", ["actor": firstActorName])
        }
    }
}

final class NotificationsViewModel: ObservableObject {
    static let shared = NotificationsViewModel()
    
    @Published var selectedFilter: NotificationFilter = .all
    @Published var items: [NotificationItem] = []
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var isLoadingMore: Bool = false
    
    private var topCursor: String?
    private var bottomCursor: String?
    
    var filteredItems: [NotificationItem] {
        switch selectedFilter {
        case .all:
            return items
        case .likesAndReposts:
            return items.filter { $0.type == .like || $0.type == .retweet }
        case .comments:
            return items.filter { $0.type == .reply }
        case .mentions:
            return items.filter { ($0.type == .mention || $0.type == .follow) && !$0.isRecentPost }
        }
    }
    
    private init() {
        loadInitialData()
    }
    
    func resetForSignOut() {
        items = []
        topCursor = nil
        bottomCursor = nil
        isLoading = false
        isRefreshing = false
        isLoadingMore = false
    }
    
    func signedIn() {
        refresh(silently: false)
    }
    
    private func loadInitialData() {
        // 1. Load cached snapshot from disk if available
        if let snapshot = NotificationCacheManager.shared.loadCachedSnapshot(), !snapshot.items.isEmpty {
            self.items = snapshot.items
            self.topCursor = snapshot.topCursor
            self.bottomCursor = snapshot.bottomCursor
            prefetchMedia(for: snapshot.items)
        }
        
        // 2. Refresh live notifications from network
        refresh(silently: !self.items.isEmpty)
    }
    
    func selectFilter(_ filter: NotificationFilter) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                self.selectedFilter = filter
            }
        }
    }
    
    func nextFilter() {
        let all = NotificationFilter.allCases
        if let idx = all.firstIndex(of: selectedFilter), idx < all.count - 1 {
            selectFilter(all[idx + 1])
        }
    }
    
    func prevFilter() {
        let all = NotificationFilter.allCases
        if let idx = all.firstIndex(of: selectedFilter), idx > 0 {
            selectFilter(all[idx - 1])
        }
    }
    
    func refresh(silently: Bool = false) {
        if !silently {
            isRefreshing = true
        }
        
        let startTime = Date()
        APIClient.shared.fetchNotifications { [weak self] result in
            let elapsed = Date().timeIntervalSince(startTime)
            let remainingDelay = max(0.0, 2.4 - elapsed)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (silently ? 0 : remainingDelay)) {
                guard let self = self else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    self.isRefreshing = false
                }
                switch result {
                case .success(let data):
                    if !data.items.isEmpty {
                        self.items = data.items
                        self.topCursor = data.topCursor
                        self.bottomCursor = data.bottomCursor
                        self.prefetchMedia(for: data.items)
                        NotificationCacheManager.shared.saveSnapshot(
                            items: data.items,
                            topCursor: data.topCursor,
                            bottomCursor: data.bottomCursor
                        )
                    } else if self.items.isEmpty {
                        self.loadMockNotifications()
                    }
                case .failure:
                    if self.items.isEmpty {
                        self.loadMockNotifications()
                    }
                }
            }
        }
    }
    
    func loadMore() {
        guard !isLoadingMore, let cursor = bottomCursor else { return }
        isLoadingMore = true
        
        APIClient.shared.fetchNotifications(cursor: cursor) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoadingMore = false
                if case .success(let data) = result {
                    var current = self.items
                    var seen = Set(current.map { $0.id })
                    for item in data.items {
                        if !seen.contains(item.id) {
                            seen.insert(item.id)
                            current.append(item)
                        }
                    }
                    self.items = current
                    self.bottomCursor = data.bottomCursor
                    self.prefetchMedia(for: data.items)
                    NotificationCacheManager.shared.saveSnapshot(
                        items: current,
                        topCursor: self.topCursor,
                        bottomCursor: self.bottomCursor
                    )
                }
            }
        }
    }
    
    private func prefetchMedia(for notifItems: [NotificationItem]) {
        var urls: [String] = []
        for item in notifItems.prefix(40) {
            for actor in item.actors {
                if let avatar = actor.avatarUrl {
                    urls.append(avatar)
                }
            }
        }
        MediaCacheManager.shared.prefetchImages(urls: urls)
    }
    
    private func loadMockNotifications() {
        let now = Date()
        self.items = [
            NotificationItem(
                id: "notif-1",
                type: .like,
                actors: [
                    TweetUser(id: "u1", name: "Lumine", screenName: "lumine_traveller", avatarUrl: nil, isVerified: true),
                    TweetUser(id: "u2", name: "Amber", screenName: "outrider_amber", avatarUrl: nil, isVerified: false)
                ],
                actionSummary: "Lumine and Amber liked your post",
                targetTweetSnippet: "Tweetintosh native macOS client Liquid Glass UI is rolling out smoothly! #SwiftUI",
                replyBody: nil,
                createdAt: now.addingTimeInterval(-180)
            ),
            NotificationItem(
                id: "notif-2",
                type: .retweet,
                actors: [
                    TweetUser(id: "u3", name: "Apple Swift", screenName: "swift_lang", avatarUrl: nil, isVerified: true)
                ],
                actionSummary: "Apple Swift reposted your post",
                targetTweetSnippet: "Building seamless macOS 26 glassEffect with fallback Gaussian blur modifiers.",
                replyBody: nil,
                createdAt: now.addingTimeInterval(-1200)
            ),
            NotificationItem(
                id: "notif-3",
                type: .reply,
                actors: [
                    TweetUser(id: "u4", name: "Design Lead", screenName: "design_system", avatarUrl: nil, isVerified: true)
                ],
                actionSummary: "Design Lead replied to your post",
                targetTweetSnippet: "The floating island sidebar and dynamic search capsule look stunning.",
                replyBody: "The in-place fade transition and continuous smooth corners feel so organic. Great HIG adherence!",
                createdAt: now.addingTimeInterval(-3600)
            ),
            NotificationItem(
                id: "notif-4",
                type: .mention,
                actors: [
                    TweetUser(id: "u5", name: "Cyan", screenName: "anno_cyan", avatarUrl: nil, isVerified: false)
                ],
                actionSummary: "Cyan mentioned you in a post",
                targetTweetSnippet: nil,
                replyBody: "@anno Check out the new Option+QWER shortcuts for the secondary notifications capsule!",
                createdAt: now.addingTimeInterval(-7200)
            ),
            NotificationItem(
                id: "notif-5",
                type: .like,
                actors: [
                    TweetUser(id: "u6", name: "Raiden Shogun", screenName: "inazuma_eternity", avatarUrl: nil, isVerified: true)
                ],
                actionSummary: "Raiden Shogun liked your post",
                targetTweetSnippet: "120Hz ProMotion skeleton shimmer and SVG handwriting pull-to-refresh.",
                replyBody: nil,
                createdAt: now.addingTimeInterval(-14400)
            )
        ]
    }
}
