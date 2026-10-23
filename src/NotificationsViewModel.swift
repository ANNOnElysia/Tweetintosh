//
//  NotificationsViewModel.swift
//  MaX - Headless Data-driven Client
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
        case .all: return "tray.full.fill"
        case .likesAndReposts: return "heart.and.arrow.trianglehead.2.clockwise"
        case .comments: return "bubble.left.and.text.bubble.right.fill"
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
    
    var relativeTime: String {
        let interval = Date().timeIntervalSince(createdAt)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
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
            return items.filter { $0.type == .mention || $0.type == .follow }
        }
    }
    
    private init() {
        loadInitialData()
    }
    
    private func loadInitialData() {
        // 1. Load cached snapshot from disk if available
        if let snapshot = NotificationCacheManager.shared.loadCachedSnapshot(), !snapshot.items.isEmpty {
            self.items = snapshot.items
            self.topCursor = snapshot.topCursor
            self.bottomCursor = snapshot.bottomCursor
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
        
        APIClient.shared.fetchNotifications { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isRefreshing = false
                switch result {
                case .success(let data):
                    if !data.items.isEmpty {
                        self.items = data.items
                        self.topCursor = data.topCursor
                        self.bottomCursor = data.bottomCursor
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
                    NotificationCacheManager.shared.saveSnapshot(
                        items: current,
                        topCursor: self.topCursor,
                        bottomCursor: self.bottomCursor
                    )
                }
            }
        }
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
                targetTweetSnippet: "MaX native macOS client Liquid Glass UI is rolling out smoothly! #SwiftUI",
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
