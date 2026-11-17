//
//  NotificationsViewModel.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import Combine
import AppKit

// The feeds X's own apps show. X builds each one on its server, so they are fetched separately rather than filtered
// here: Priority is everything from people you follow, and Mentions is replies and @mentions.
enum NotificationFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case priority = 1
    case mentions = 2
    
    var id: Int { rawValue }
    
    var endpoint: String {
        switch self {
        case .all: return "all"
        case .priority: return "priority"
        case .mentions: return "mentions"
        }
    }
    
    var titleKey: String {
        switch self {
        case .all: return "notif_filter_all"
        case .priority: return "notif_filter_priority"
        case .mentions: return "notif_filter_mentions"
        }
    }
    
    var iconName: String {
        switch self {
        case .all: return "tray.fill"
        case .priority: return "star.fill"
        case .mentions: return "at"
        }
    }
    
    var shortcutKey: String {
        switch self {
        case .all: return "⌥Q"
        case .priority: return "⌥W"
        case .mentions: return "⌥E"
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
    // The post the notification is about, so the row can open it and list who liked or reposted it
    var targetTweetId: String? = nil
    // The first picture of that post, for the thumbnail beside the row
    var thumbnailUrl: String? = nil
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
    
    @Published private(set) var selectedFilter: NotificationFilter = .all
    // What the list is showing. It trails `selectedFilter` until the chosen feed has rows to show, so a filter
    // change animates as rows leaving and arriving in one list instead of the list being replaced.
    @Published private(set) var displayedFilter: NotificationFilter = .all
    @Published private(set) var displayedItems: [NotificationItem] = []
    // Rows on their way out: faded where they stand before their space collapses.
    @Published private(set) var fadingItemIDs: Set<String> = []
    @Published private var feeds: [NotificationFilter: FeedState] = [:]

    private struct Page {
        var items: [NotificationItem]
        var topCursor: String?
        var bottomCursor: String?
        var refreshedAt: Date
    }

    private struct FeedState {
        var page: Page?
        var refreshID: UUID?
        var paginationID: UUID?
        var showsRefresh = false
        var failed = false
    }

    // Leaving rows fade in place first, then the survivors close the gap
    private static let leaveDuration = 0.12
    private static let settleDuration = 0.22
    // A fast refresh still shows its spinner for this long, without holding the rows back
    private static let minimumRefreshDuration: TimeInterval = 2.4
    // Which refresh owns each feed's spinner, so a stale timer cannot end a newer one's
    private var refreshIndicators: [NotificationFilter: UUID] = [:]
    private var transitionID = UUID()

    var isRefreshing: Bool {
        feeds[selectedFilter]?.showsRefresh == true
    }

    var hasFailed: Bool {
        feeds[selectedFilter]?.failed == true
    }

    /// The selected feed has no rows yet and is on its way.
    var isAwaitingSelectedFeed: Bool {
        feeds[selectedFilter]?.page == nil && feeds[selectedFilter]?.refreshID != nil
    }

    /// Nothing is on screen and the selected feed is on its way, so it is not empty yet.
    var isLoadingSelectedFeed: Bool {
        displayedItems.isEmpty && isAwaitingSelectedFeed
    }

    // Handed to the list, which animates only changes to these values; the same timing the model uses
    var leaveAnimation: Animation? { Self.motion(Self.leaveDuration) }
    var settleAnimation: Animation? { Self.motion(Self.settleDuration) }
    
    private init() {
        loadInitialData()
    }
    
    func resetForSignOut() {
        // Clearing the request IDs also rejects callbacks from the previous account.
        feeds = [:]
        selectedFilter = .all
        displayedFilter = .all
        displayedItems = []
        fadingItemIDs = []
        refreshIndicators = [:]
        transitionID = UUID()
    }
    
    func signedIn() {
        refresh(silently: false)
    }

    /// Loads the categories that have never loaded, so picking one animates from the current rows instead of waiting
    /// for the network. Silent: nothing on screen changes until the reader picks a category.
    func preloadMissingFeeds() {
        guard AccountManager.shared.active != nil else { return }
        for feed in NotificationFilter.allCases where feeds[feed]?.page == nil && feeds[feed]?.refreshID == nil {
            refresh(silently: true, feed: feed)
        }
    }
    
    private func loadInitialData() {
        // 1. Load cached snapshot from disk if available
        if let snapshot = NotificationCacheManager.shared.loadCachedSnapshot(), !snapshot.items.isEmpty {
            feeds[.all] = FeedState(page: Page(items: snapshot.items, topCursor: snapshot.topCursor,
                                             bottomCursor: snapshot.bottomCursor, refreshedAt: snapshot.savedAt))
            displayedItems = snapshot.items
            prefetchMedia(for: snapshot.items)
        }
        
        // 2. Refresh live notifications from network
        refresh(silently: feeds[.all]?.page != nil)
    }
    
    func selectFilter(_ filter: NotificationFilter) {
        selectedFilter = filter
        if let page = feeds[filter]?.page {
            transition(to: filter, items: page.items)
        } else {
            // Nothing to show yet: keep the current rows, undoing any half-finished fade so they stay visible.
            cancelPendingTransition()
        }
        if let refreshedAt = feeds[filter]?.page?.refreshedAt,
           Date().timeIntervalSince(refreshedAt) < 60 { return }
        refresh(silently: true, feed: filter)
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
    
    func refresh(silently: Bool = false, feed: NotificationFilter? = nil) {
        let feed = feed ?? selectedFilter
        var state = feeds[feed] ?? FeedState()
        guard state.refreshID == nil else { return }
        let requestID = UUID()
        state.refreshID = requestID
        // A refreshed first page makes any outstanding pagination response obsolete.
        state.paginationID = nil
        state.showsRefresh = !silently
        state.failed = false
        feeds[feed] = state
        if !silently { refreshIndicators[feed] = requestID }

        let startTime = Date()
        APIClient.shared.fetchNotifications(feed: feed) { [weak self] result in
            let remaining = max(0.0, Self.minimumRefreshDuration - Date().timeIntervalSince(startTime))

            DispatchQueue.main.async {
                guard let self = self, var state = self.feeds[feed], state.refreshID == requestID else { return }
                state.refreshID = nil
                switch result {
                case .success(let data):
                    state.page = Page(items: data.items, topCursor: data.topCursor,
                                      bottomCursor: data.bottomCursor, refreshedAt: Date())
                    self.store(state, for: feed)
                    self.applyIfSelected(feed)
                    self.prefetchMedia(for: data.items)
                case .failure:
                    state.failed = true
                    self.feeds[feed] = state
                }
                if !silently { self.endRefreshIndicator(feed: feed, requestID: requestID, after: remaining) }
            }
        }
    }

    // The rows are already up to date when this runs; only the spinner waits out its minimum.
    private func endRefreshIndicator(feed: NotificationFilter, requestID: UUID, after delay: TimeInterval) {
        let finish = { [weak self] in
            guard let self, self.refreshIndicators[feed] == requestID,
                  var state = self.feeds[feed] else { return }
            self.refreshIndicators[feed] = nil
            state.showsRefresh = false
            self.feeds[feed] = state
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: finish)
        } else {
            finish()
        }
    }
    
    func loadMore() {
        let feed = selectedFilter
        guard var state = feeds[feed], state.refreshID == nil, state.paginationID == nil,
              let cursor = state.page?.bottomCursor else { return }
        let requestID = UUID()
        state.paginationID = requestID
        feeds[feed] = state

        APIClient.shared.fetchNotifications(feed: feed, cursor: cursor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, var state = self.feeds[feed], state.paginationID == requestID,
                      var page = state.page else { return }
                state.paginationID = nil
                if case .success(let data) = result {
                    var seen = Set(page.items.map { $0.id })
                    for item in data.items where seen.insert(item.id).inserted {
                        page.items.append(item)
                    }
                    page.bottomCursor = data.bottomCursor
                    state.page = page
                    self.store(state, for: feed)
                    self.applyIfSelected(feed)
                    self.prefetchMedia(for: data.items)
                } else {
                    self.feeds[feed] = state
                }
            }
        }
    }

    private func applyIfSelected(_ feed: NotificationFilter) {
        guard selectedFilter == feed, let page = feeds[feed]?.page else { return }
        transition(to: feed, items: page.items)
    }

    /// Moves the list from what it shows to `feed`'s rows. Rows both feeds share keep their identity and slide into
    /// place; the ones only the old feed has fade first, so the change reads as notifications being filtered out
    /// rather than a new page being swapped in.
    private func transition(to feed: NotificationFilter, items: [NotificationItem]) {
        guard displayedFilter != feed else {
            commit(feed, items)
            return
        }
        let targetIDs = Set(items.map(\.id))
        let leaving = displayedItems.map(\.id).filter { !targetIDs.contains($0) }
        guard !leaving.isEmpty else {
            commit(feed, items)
            return
        }
        let id = UUID()
        transitionID = id
        withAnimation(Self.motion(Self.leaveDuration)) {
            fadingItemIDs = Set(leaving)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.leaveDuration) { [weak self] in
            guard let self = self, self.transitionID == id, self.selectedFilter == feed,
                  let page = self.feeds[feed]?.page else { return }
            self.commit(feed, page.items)
        }
    }

    private func cancelPendingTransition() {
        transitionID = UUID()
        guard !fadingItemIDs.isEmpty else { return }
        withAnimation(Self.motion(Self.leaveDuration)) {
            fadingItemIDs = []
        }
    }

    private func commit(_ feed: NotificationFilter, _ items: [NotificationItem]) {
        transitionID = UUID()
        guard displayedFilter != feed || displayedItems != items || !fadingItemIDs.isEmpty else { return }
        withAnimation(Self.motion(Self.settleDuration)) {
            displayedFilter = feed
            displayedItems = items
            fadingItemIDs = []
        }
    }

    // Reduce Motion keeps the row changes but drops the movement, as the HIG asks of repeated transitions.
    private static func motion(_ duration: Double) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: duration)
    }
    
    // Only All is kept on disk: it is the one shown on launch
    private func store(_ state: FeedState, for feed: NotificationFilter) {
        feeds[feed] = state
        if feed == .all, let page = state.page {
            NotificationCacheManager.shared.saveSnapshot(items: page.items, topCursor: page.topCursor, bottomCursor: page.bottomCursor)
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
}
