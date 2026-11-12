//
//  TimelineViewModel.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import os

private let pollLogger = Logger(subsystem: "com.anno.tweetintosh", category: "preload")
private let pagingLogger = Logger(subsystem: "com.anno.tweetintosh", category: "paging")
// Observed per property: it holds all four feeds and their pending posts, and a background poll of one feed shouldn't
// redraw the timeline of another.
@Observable
final class TimelineViewModel {
    static let shared = TimelineViewModel()
    
    var selectedFeed: HomeFeedType = .forYou {
        didSet {
            updateActiveTweets()
        }
    }
    
    var tweets: [Tweet] = []
    
    // Official Twitter Lists for authenticated account
    var userLists: [TwitterList] = []
    var selectedListId: String = ""
    var isLoadingLists: Bool = false
    
    var selectedList: TwitterList? {
        userLists.first { $0.id == selectedListId } ?? userLists.first
    }
    
    // Independent storage for each feed
    var forYouTweets: [Tweet] = []
    var followingTweets: [Tweet] = []
    var bookmarkTweets: [Tweet] = []
    var listTweets: [String: [Tweet]] = [:]
    
    // Pending new tweets buffer (holds background/auto-fetched tweets so user reading is never disrupted or pushed down)
    var forYouPendingTweets: [Tweet] = []
    var followingPendingTweets: [Tweet] = []
    var listPendingTweets: [String: [Tweet]] = [:]
    
    var isLoadingInitial = true
    var isRefreshing = false
    var isLoadingMore = false
    var isAuthenticated = false
    var errorMessage: String?
    @ObservationIgnored private var isReturningToTop = false
    
    @ObservationIgnored private var forYouTopCursor: String?
    @ObservationIgnored private var forYouBottomCursor: String?
    
    @ObservationIgnored private var followingTopCursor: String?
    @ObservationIgnored private var followingBottomCursor: String?

    @ObservationIgnored private var bookmarksTopCursor: String?
    @ObservationIgnored private var bookmarksBottomCursor: String?
    
    @ObservationIgnored private var listTopCursors: [String: String] = [:]
    @ObservationIgnored private var listBottomCursors: [String: String] = [:]
    
    // Track seen tweet IDs for the algorithmic "For You" feed
    @ObservationIgnored private var seenTweetIds: [String] = []
    
    // Every cursor is read and written for the feed that asked for it, never for whichever feed happens to be on
    // screen when the answer arrives: a page requested for one list must not move another list's chain.
    private func topCursor(for feed: HomeFeedType, listId: String) -> String? {
        switch feed {
        case .forYou: return forYouTopCursor
        case .following: return followingTopCursor
        case .bookmarks: return bookmarksTopCursor
        case .list: return listTopCursors[listId]
        }
    }
    
    private func setTopCursor(_ cursor: String?, for feed: HomeFeedType, listId: String) {
        switch feed {
        case .forYou: forYouTopCursor = cursor
        case .following: followingTopCursor = cursor
        case .bookmarks: bookmarksTopCursor = cursor
        case .list: listTopCursors[listId] = cursor
        }
    }
    
    private func bottomCursor(for feed: HomeFeedType, listId: String) -> String? {
        switch feed {
        case .forYou: return forYouBottomCursor
        case .following: return followingBottomCursor
        case .bookmarks: return bookmarksBottomCursor
        case .list: return listBottomCursors[listId]
        }
    }
    
    private func setBottomCursor(_ cursor: String?, for feed: HomeFeedType, listId: String) {
        switch feed {
        case .forYou: forYouBottomCursor = cursor
        case .following: followingBottomCursor = cursor
        case .bookmarks: bookmarksBottomCursor = cursor
        case .list: listBottomCursors[listId] = cursor
        }
    }
    
    // MARK: - Bottom-of-Feed Paging
    
    // What the bottom of the feed is doing. The footer shows this instead of a spinner that never resolves, and only a
    // page request that actually ran decides that the chain has stopped.
    enum FeedPagingState: Equatable {
        case idle
        case loading
        case failed
        // Pages came back empty while the cursor kept moving: there may be more, but not by asking again straight away
        case empty
        // The page request said there is nothing below it, or a cursor came back that cannot advance
        case ended
    }
    
    private struct PagingKey: Hashable {
        let feed: HomeFeedType
        let listId: String
    }
    
    // One feed's chain: what its bottom is doing, and what it has already tried
    private struct Paging {
        var state: FeedPagingState = .idle
        // Pages in a row that brought nothing new
        var emptyPages = 0
        // Failed requests in a row, which decide whether one more is tried on its own
        var failures = 0
        var retry: DispatchWorkItem?
    }
    
    // The selected feed's state, which is what the footer reads
    var pagingState: FeedPagingState = .idle
    
    @ObservationIgnored private var paging: [PagingKey: Paging] = [:]
    // Feeds whose posts came from a snapshot that cannot be continued, so the first fresh page replaces them
    @ObservationIgnored private var awaitingRebuild: Set<PagingKey> = []
    // Bumped when the account changes, so an answer for the previous account is dropped rather than merged
    @ObservationIgnored private var accountSession = 0
    
    private var currentPagingKey: PagingKey {
        PagingKey(feed: selectedFeed, listId: selectedFeed == .list ? selectedListId : "")
    }
    
    private func setPagingState(_ state: FeedPagingState, for key: PagingKey) {
        paging[key, default: Paging()].state = state
        if key == currentPagingKey { pagingState = state }
    }
    
    init() {
        let cachedLists = TimelineCacheManager.shared.loadCachedUserLists()
        self.userLists = cachedLists
        if let first = cachedLists.first, selectedListId.isEmpty {
            self.selectedListId = first.id
        }
        checkAuth()
        startPolling()
        fetchUserLists()
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("Tweetintosh_PromotedPostsSettingDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !ThemeManager.shared.showPromotedPosts {
                self.forYouTweets.removeAll { $0.isPromoted }
                self.followingTweets.removeAll { $0.isPromoted }
                for (key, list) in self.listTweets {
                    self.listTweets[key] = list.filter { !$0.isPromoted }
                }
                self.updateActiveTweets()
            } else {
                self.refresh(silently: false, isUserInitiated: true)
            }
        }
    }
    
    // MARK: - Background Polling
    // Checks for new posts on the intervals X's web client uses (gryphon_timeline_polling_*): every 30 s on
    // chronological feeds (Following, lists) and every 2 minutes on For You. New posts are queued behind the
    // floating "N new posts" pill, never inserted under the reader. Polling pauses while the app is in the
    // background or off the Home tab, and catches up as soon as it comes back.
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var lastFetchAt = Date()
    
    private func pollInterval(for feed: HomeFeedType) -> TimeInterval {
        feed == .forYou ? 120 : 30
    }
    
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.pollIfDue()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
    
    private func pollIfDue() {
        guard isAuthenticated, !isRefreshing, !isLoadingInitial, !isLoadingMore else { return }
        guard NSApp.isActive, NavigationManager.shared.currentTab == .home,
              let window = NSApp.mainWindow, window.isVisible, !window.isMiniaturized else { return }
        guard selectedFeed != .bookmarks else { return }
        guard Date().timeIntervalSince(lastFetchAt) >= pollInterval(for: selectedFeed) else { return }
        pollLogger.notice("poll \(self.selectedFeed.rawValue, privacy: .public)")
        refresh(silently: true, isUserInitiated: false)
    }
    
    func fetchUserLists(completion: (() -> Void)? = nil) {
        isLoadingLists = true
        APIClient.shared.fetchUserLists { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingLists = false
                switch result {
                case .success(let lists):
                    self.userLists = lists
                    TimelineCacheManager.shared.saveCachedUserLists(lists)
                    if !lists.isEmpty {
                        if self.selectedListId.isEmpty || !lists.contains(where: { $0.id == self.selectedListId }) {
                            self.selectedListId = lists.first?.id ?? ""
                        }
                    } else {
                        // User has no lists! Fallback to forYou if currently on list feed
                        if self.selectedFeed == .list {
                            self.selectedFeed = .forYou
                            self.updateActiveTweets()
                        }
                    }
                case .failure:
                    if self.userLists.isEmpty && self.selectedFeed == .list {
                        self.selectedFeed = .forYou
                        self.updateActiveTweets()
                    }
                }
                completion?()
            }
        }
    }
    
    func selectList(_ list: TwitterList) {
        selectedListId = list.id
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedFeed = .list
        }
        updateActiveTweets()
        if (listTweets[list.id] ?? []).isEmpty {
            refresh(silently: false, isUserInitiated: false)
        }
    }
    
    // Back to the signed-out state: nothing from the previous account stays on screen, and the login prompt shows
    func resetForSignOut() {
        isAuthenticated = false
        isLoadingInitial = false
        isRefreshing = false
        isLoadingMore = false
        errorMessage = nil
        tweets = []
        forYouTweets = []
        followingTweets = []
        listTweets = [:]
        forYouPendingTweets = []
        followingPendingTweets = []
        listPendingTweets = [:]
        forYouTopCursor = nil
        forYouBottomCursor = nil
        followingTopCursor = nil
        followingBottomCursor = nil
        listTopCursors = [:]
        listBottomCursors = [:]
        seenTweetIds = []
        paging.values.forEach { $0.retry?.cancel() }
        paging = [:]
        awaitingRebuild = []
        pagingState = .idle
        accountSession += 1
        userLists = []
        selectedListId = ""
    }
    
    // After a login: the same checks and first load as at launch
    func signedIn() {
        accountSession += 1
        isLoadingInitial = true
        checkAuth()
        fetchUserLists()
    }
    
    func checkAuth() {
        if let creds = CredentialsManager.shared.loadCredentials(), creds.isValid {
            self.isAuthenticated = true
            loadTimeline()
        } else {
            // Check default WebKit store first
            CredentialsManager.shared.tryExtractFromDefaultStore { [weak self] creds in
                if let creds = creds, creds.isValid {
                    self?.isAuthenticated = true
                    self?.loadTimeline()
                } else {
                    self?.isAuthenticated = false
                    self?.isLoadingInitial = false
                }
            }
        }
    }
    
    func loadTimeline() {
        // 1. Immediately load local caches for instantaneous 0ms display
        if let cachedForYou = TimelineCacheManager.shared.loadCachedSnapshot(feed: .forYou), !cachedForYou.tweets.isEmpty {
            self.forYouTweets = cachedForYou.tweets
            self.forYouTopCursor = cachedForYou.topCursor
            self.forYouBottomCursor = cachedForYou.bottomCursor
            self.seenTweetIds = Array(cachedForYou.tweets.prefix(40).map { $0.id })
            self.prefetchMedia(for: cachedForYou.tweets)
            self.expectRebuildIfCachedPostsCannotContinue(cachedForYou, key: PagingKey(feed: .forYou, listId: ""))
        }
        
        if let cachedFollowing = TimelineCacheManager.shared.loadCachedSnapshot(feed: .following), !cachedFollowing.tweets.isEmpty {
            self.followingTweets = cachedFollowing.tweets
            self.followingTopCursor = cachedFollowing.topCursor
            self.followingBottomCursor = cachedFollowing.bottomCursor
            self.prefetchMedia(for: cachedFollowing.tweets)
            self.expectRebuildIfCachedPostsCannotContinue(cachedFollowing, key: PagingKey(feed: .following, listId: ""))
        }
        
        if let cachedBookmarks = TimelineCacheManager.shared.loadCachedSnapshot(feed: .bookmarks), !cachedBookmarks.tweets.isEmpty {
            self.bookmarkTweets = cachedBookmarks.tweets
            self.bookmarksTopCursor = cachedBookmarks.topCursor
            self.bookmarksBottomCursor = cachedBookmarks.bottomCursor
        }
        
        if let cachedList = TimelineCacheManager.shared.loadCachedSnapshot(feed: .list, listId: selectedListId), !cachedList.tweets.isEmpty {
            self.listTweets[selectedListId] = cachedList.tweets
            self.listTopCursors[selectedListId] = cachedList.topCursor
            self.listBottomCursors[selectedListId] = cachedList.bottomCursor
            self.prefetchMedia(for: cachedList.tweets)
            self.expectRebuildIfCachedPostsCannotContinue(cachedList, key: PagingKey(feed: .list, listId: selectedListId))
        }
        
        updateActiveTweets()
        if !tweets.isEmpty {
            self.isLoadingInitial = false
        }
        
        // 2. Fetch fresh posts from GraphQL API (Fetch once on launch/restart)
        refresh(silently: !tweets.isEmpty, isUserInitiated: false)
    }
    
    // A snapshot that was cut down to fit, or written before completeness was recorded, cannot be continued: its
    // cursor (if it has one) points past the posts it holds, and a fresh first page may not overlap them in either
    // direction. Its posts stay on screen for the instant launch, then the first page replaces them.
    private func expectRebuildIfCachedPostsCannotContinue(_ snapshot: TimelineSnapshot, key: PagingKey) {
        guard snapshot.isComplete != true || snapshot.bottomCursor == nil else { return }
        awaitingRebuild.insert(key)
    }
    
    private func updateActiveTweets() {
        switch selectedFeed {
        case .forYou:
            self.tweets = forYouTweets
        case .following:
            self.tweets = followingTweets
        case .bookmarks:
            self.tweets = bookmarkTweets
        case .list:
            self.tweets = listTweets[selectedListId] ?? []
        }
        pagingState = paging[currentPagingKey]?.state ?? .idle
    }
    
    func pendingCount(for feed: HomeFeedType, listId: String? = nil) -> Int {
        switch feed {
        case .forYou: return forYouPendingTweets.count
        case .following: return followingPendingTweets.count
        case .bookmarks: return 0
        case .list: return listPendingTweets[listId ?? selectedListId]?.count ?? 0
        }
    }
    
    // `listId` is the list the posts belong to, not whichever one is selected when the answer arrives
    func enqueuePendingTweets(_ newTweets: [Tweet], for feed: HomeFeedType, listId: String? = nil) {
        switch feed {
        case .forYou:
            let existingPendingIds = Set(forYouPendingTweets.map { $0.id })
            let trulyNew = newTweets.filter { !existingPendingIds.contains($0.id) }
            forYouPendingTweets.insert(contentsOf: trulyNew, at: 0)
        case .following:
            let existingPendingIds = Set(followingPendingTweets.map { $0.id })
            let trulyNew = newTweets.filter { !existingPendingIds.contains($0.id) }
            followingPendingTweets.insert(contentsOf: trulyNew, at: 0)
        case .bookmarks:
            // Never queued: the bookmarks page always shows them as they are
            break
        case .list:
            let listId = listId ?? selectedListId
            var currentPending = listPendingTweets[listId] ?? []
            let existingPendingIds = Set(currentPending.map { $0.id })
            let trulyNew = newTweets.filter { !existingPendingIds.contains($0.id) }
            currentPending.insert(contentsOf: trulyNew, at: 0)
            listPendingTweets[listId] = currentPending
        }
    }
    
    // Drops posts queued for a feed whose list is being replaced by a fresh first page, which already holds them
    private func clearPending(for feed: HomeFeedType, listId: String) {
        switch feed {
        case .forYou: forYouPendingTweets = []
        case .following: followingPendingTweets = []
        case .bookmarks: break
        case .list: listPendingTweets[listId] = []
        }
        if selectedFeed == feed, feed != .list || selectedListId == listId {
            TimelineScrollCoordinator.shared.unreadCountAbove = 0
        }
    }
    
    func applyPendingTweets(for feed: HomeFeedType) {
        let listId = feed == .list ? selectedListId : ""
        let pending: [Tweet]
        switch feed {
        case .forYou: pending = forYouPendingTweets
        case .following: pending = followingPendingTweets
        case .bookmarks: pending = []
        case .list: pending = listPendingTweets[listId] ?? []
        }
        guard !pending.isEmpty else { return }
        
        var updated = self.currentFeedTweets(feed, listId: listId)
        updated.insert(contentsOf: pending, at: 0)
        self.setFeedTweets(updated, for: feed, listId: listId)
        
        switch feed {
        case .forYou:
            forYouPendingTweets = []
            let newIds = pending.map { $0.id }
            self.seenTweetIds = Array(Set(newIds + self.seenTweetIds).prefix(60))
        case .following:
            followingPendingTweets = []
        case .bookmarks:
            break
        case .list:
            listPendingTweets[listId] = []
        }
        
        TimelineCacheManager.shared.saveSnapshot(
            feed: feed,
            listId: feed == .list ? listId : nil,
            tweets: updated,
            topCursor: topCursor(for: feed, listId: listId),
            bottomCursor: bottomCursor(for: feed, listId: listId)
        )
        
        if selectedFeed == feed {
            updateActiveTweets()
            TimelineScrollCoordinator.shared.unreadCountAbove = 0
        }
    }
    
    // Manual refresh returns to the top before inserting queued posts, so the current viewport never jumps.
    func reloadFromShortcut() {
        guard !isRefreshing, !isReturningToTop else { return }
        isReturningToTop = true
        let feed = selectedFeed
        let listID = selectedListId
        TimelineScrollCoordinator.shared.scrollToTop { [weak self] in
            guard let self else { return }
            self.isReturningToTop = false
            guard NavigationManager.shared.currentTab == .home,
                  self.selectedFeed == feed, self.selectedListId == listID, !self.isRefreshing else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.applyPendingTweets(for: feed)
            }
            self.refresh(silently: false, isUserInitiated: true)
        }
    }
    
    // MARK: - Feed Switching
    func selectFeed(_ feed: HomeFeedType) {
        if feed == .list && userLists.isEmpty { return }
        guard selectedFeed != feed else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedFeed = feed
        }
        updateActiveTweets()
        TimelineScrollCoordinator.shared.unreadCountAbove = pendingCount(for: feed)
        
        if tweets.isEmpty {
            refresh(silently: false, isUserInitiated: false)
        } else if feed == .bookmarks {
            refresh(silently: true, isUserInitiated: false)
        }
    }
    
    func nextFeed() {
        let all: [HomeFeedType] = userLists.isEmpty ? [.forYou, .following, .bookmarks] : HomeFeedType.allCases
        if let idx = all.firstIndex(of: selectedFeed) {
            let nextIdx = (idx + 1) % all.count
            selectFeed(all[nextIdx])
        }
    }
    
    func prevFeed() {
        let all: [HomeFeedType] = userLists.isEmpty ? [.forYou, .following, .bookmarks] : HomeFeedType.allCases
        if let idx = all.firstIndex(of: selectedFeed) {
            let prevIdx = (idx - 1 + all.count) % all.count
            selectFeed(all[prevIdx])
        }
    }
    
    // MARK: - Refresh (Pull or Initial)
    func refresh(silently: Bool = false, isUserInitiated: Bool = false) {
        lastFetchAt = Date()
        if !silently {
            isRefreshing = true
        }

        let currentFeed = selectedFeed
        let listID = currentFeed == .list ? selectedListId : ""
        let key = PagingKey(feed: currentFeed, listId: listID)
        let requestSession = accountSession
        let seenIdsToSend = (currentFeed == .forYou) ? seenTweetIds : []
        let startTime = Date()
        
        APIClient.shared.fetchGraphQLHomeTimeline(
            feedType: currentFeed,
            listId: currentFeed == .list ? listID : nil,
            cursor: nil,
            seenTweetIds: seenIdsToSend
        ) { [weak self] result in
            let elapsed = Date().timeIntervalSince(startTime)
            let minDisplayDuration: Double = isUserInitiated ? 2.4 : 1.2
            let remainingDelay = max(0.0, minDisplayDuration - elapsed)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (silently ? 0 : remainingDelay)) {
                // A refresh for the previous account must not paint over the new one's feed
                guard let self = self, self.accountSession == requestSession else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    self.isRefreshing = false
                    self.isLoadingInitial = false
                }
                
                switch result {
                case .success(let payload):
                    self.errorMessage = nil
                    if currentFeed == .bookmarks {
                        // Bookmarks are taken away as well as added, anywhere, so the newest page replaces the list
                        // rather than being merged into it
                        self.setFeedTweets(payload.tweets, for: .bookmarks, listId: "")
                        self.setTopCursor(payload.topCursor, for: .bookmarks, listId: "")
                        self.setBottomCursor(payload.bottomCursor, for: .bookmarks, listId: "")
                        self.resetPaging(for: key)
                        TimelineCacheManager.shared.saveSnapshot(feed: .bookmarks, tweets: payload.tweets,
                                                                 topCursor: payload.topCursor, bottomCursor: payload.bottomCursor)
                        if self.selectedFeed == .bookmarks { self.updateActiveTweets() }
                        break
                    }
                    let existingIds = Set(self.currentFeedTweets(currentFeed, listId: listID).map { $0.id })
                    let newOnes = payload.tweets.filter { !existingIds.contains($0.id) }
                    
                    let rebuildsCache = self.awaitingRebuild.contains(key)
                    if self.currentFeedTweets(currentFeed, listId: listID).isEmpty
                        || (rebuildsCache && !payload.tweets.isEmpty) {
                        // The chain starts from this page. Cached posts that could not be continued give way to it,
                        // since appending its older pages under them could put newer posts below older ones. An empty
                        // first page leaves them on screen and the rebuilding for the next refresh.
                        self.awaitingRebuild.remove(key)
                        self.setFeedTweets(payload.tweets, for: currentFeed, listId: listID)
                        self.setTopCursor(payload.topCursor, for: currentFeed, listId: listID)
                        self.setBottomCursor(payload.bottomCursor, for: currentFeed, listId: listID)
                        self.clearPending(for: currentFeed, listId: listID)
                        if currentFeed == .forYou {
                            self.seenTweetIds = Array(payload.tweets.prefix(40).map { $0.id })
                        }
                        self.resetPaging(for: key)
                        
                        TimelineCacheManager.shared.saveSnapshot(
                            feed: currentFeed,
                            listId: currentFeed == .list ? listID : nil,
                            tweets: payload.tweets,
                            topCursor: payload.topCursor,
                            bottomCursor: payload.bottomCursor
                        )
                        self.prefetchMedia(for: payload.tweets)
                    } else if !newOnes.isEmpty {
                        // Only prepend immediately if user explicitly requested a pull refresh AND is currently at the top of the feed
                        let shouldPrependImmediately = isUserInitiated && TimelineScrollState.shared.isAtTop
                        
                        if shouldPrependImmediately {
                            // User intentionally pulled down to refresh while at top: prepend new ones immediately!
                            var updated = self.currentFeedTweets(currentFeed, listId: listID)
                            updated.insert(contentsOf: newOnes, at: 0)
                            self.setFeedTweets(updated, for: currentFeed, listId: listID)
                            
                            if let newTop = payload.topCursor {
                                self.setTopCursor(newTop, for: currentFeed, listId: listID)
                            }
                            if currentFeed == .forYou {
                                let newIds = newOnes.map { $0.id }
                                self.seenTweetIds = Array(Set(newIds + self.seenTweetIds).prefix(60))
                            }
                            
                            TimelineCacheManager.shared.saveSnapshot(
                                feed: currentFeed,
                                listId: currentFeed == .list ? listID : nil,
                                tweets: updated,
                                topCursor: self.topCursor(for: currentFeed, listId: listID),
                                bottomCursor: self.bottomCursor(for: currentFeed, listId: listID)
                            )
                            self.prefetchMedia(for: newOnes)
                            
                            if self.selectedFeed == currentFeed {
                                self.updateActiveTweets()
                                TimelineScrollCoordinator.shared.unreadCountAbove = 0
                            }
                        } else {
                            // Reading in progress or background refresh:
                            // NEVER disrupt the user's reading or push their current tweet down!
                            // Enqueue to pending buffer and show the clean floating pill!
                            self.enqueuePendingTweets(newOnes, for: currentFeed, listId: listID)
                            self.prefetchMedia(for: newOnes)
                            
                            if self.selectedFeed == currentFeed, currentFeed != .list || self.selectedListId == listID {
                                TimelineScrollCoordinator.shared.unreadCountAbove = self.pendingCount(for: currentFeed, listId: listID)
                            }
                        }
                    } else {
                        // When no new tweets arrive, only the top of the feed is news: the reader's list is never blown
                        // away, and the chain's own cursor is the only one that continues what they can still scroll.
                        if let newTop = payload.topCursor {
                            self.setTopCursor(newTop, for: currentFeed, listId: listID)
                        }
                    }
                    
                    if self.selectedFeed == currentFeed {
                        self.updateActiveTweets()
                    }
                    ListLoadMoreWatcher.shared.reevaluate()
                    
                case .failure(let err):
                    if case .unauthenticated = err {
                        self.isAuthenticated = false
                    }
                    if self.tweets.isEmpty {
                        self.errorMessage = err.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Infinite Scroll Load More
    
    // Called when the reader is near the bottom, and again after every page: a page that arrives grows the content
    // without moving the scroll position, so nothing else would ask for the next one and the feed would stop with
    // room still on screen.
    func loadMore() {
        loadMore(isScrollTriggered: true)
    }
    
    // The reader tapped the footer, or a failed page is being tried again on its own. Neither is held to the rule that
    // keeps scrolling from re-asking for a page that just failed or ran out.
    func retryLoadMore() {
        let key = currentPagingKey
        paging[key]?.emptyPages = 0
        paging[key]?.failures = 0
        loadMore(isScrollTriggered: false)
    }
    
    private func loadMore(isScrollTriggered: Bool) {
        guard !isLoadingMore, !isRefreshing else { return }
        // Scrolling pages only while the timeline is what the reader is looking at; a tap always goes through
        if isScrollTriggered, NavigationManager.shared.currentTab != .home || NavigationManager.shared.hasOverlay {
            return
        }
        
        let feed = selectedFeed
        let listId = feed == .list ? selectedListId : ""
        let key = PagingKey(feed: feed, listId: listId)
        let state = paging[key]?.state ?? .idle
        guard state != .loading else { return }
        if isScrollTriggered, state == .failed || state == .empty || state == .ended {
            return
        }
        
        // No cursor is not proof that X has nothing more: it is a chain this client cannot continue (a cut-down cache,
        // or a page whose cursors were not read). Saying "no more posts" here would be a guess; the footer stays quiet
        // until a page request says the chain has stopped.
        guard let cursor = bottomCursor(for: feed, listId: listId) else {
            setPagingState(.idle, for: key)
            return
        }
        
        isLoadingMore = true
        // A scheduled retry must not fire on top of the page this request is already bringing back
        paging[key]?.retry?.cancel()
        paging[key]?.retry = nil
        setPagingState(.loading, for: key)
        let requestSession = accountSession
        
        APIClient.shared.fetchGraphQLHomeTimeline(
            feedType: feed,
            listId: feed == .list ? listId : nil,
            cursor: cursor,
            seenTweetIds: feed == .forYou ? seenTweetIds : []
        ) { [weak self] result in
            DispatchQueue.main.async {
                // Checked before anything is written: an answer for the previous account must not clear the new
                // account's loading flag or land in its feeds.
                guard let self = self, self.accountSession == requestSession else { return }
                self.isLoadingMore = false
                self.finishPage(result, feed: feed, listId: listId, key: key, cursor: cursor)
            }
        }
    }
    
    private func finishPage(
        _ result: Result<(tweets: [Tweet], topCursor: String?, bottomCursor: String?), APIError>,
        feed: HomeFeedType,
        listId: String,
        key: PagingKey,
        cursor: String
    ) {
        // A refresh replaced the chain while this page was in flight: its cursor no longer continues what is on
        // screen, and stitching it in would leave a hole in the feed. That refresh already reset this chain's state.
        guard bottomCursor(for: feed, listId: listId) == cursor else { return }
        
        switch result {
        case .success(let payload):
            let existingIds = Set(currentFeedTweets(feed, listId: listId).map { $0.id })
            let olderOnes = payload.tweets.filter { !existingIds.contains($0.id) }
            
            var updated = currentFeedTweets(feed, listId: listId)
            updated.append(contentsOf: olderOnes)
            setFeedTweets(updated, for: feed, listId: listId)
            
            // Only a cursor the server moved on from continues the chain; reusing one it repeats would ask for the
            // same page for ever, which reads as a feed that never grows.
            let nextCursor = payload.bottomCursor
            let advanced = nextCursor != nil && nextCursor != cursor
            if let nextCursor, advanced {
                setBottomCursor(nextCursor, for: feed, listId: listId)
            }
            
            if olderOnes.isEmpty {
                paging[key, default: Paging()].emptyPages += 1
            } else {
                paging[key]?.emptyPages = 0
                paging[key]?.failures = 0
            }
            
            if !advanced {
                setPagingState(.ended, for: key)
            } else if olderOnes.isEmpty, paging[key]?.emptyPages ?? 0 >= 3 {
                // Three empty pages running with the cursor still moving: there may be more, but not on its own
                setPagingState(.empty, for: key)
            } else {
                setPagingState(.idle, for: key)
            }
            
            if selectedFeed == feed, feed != .list || selectedListId == listId {
                updateActiveTweets()
            }
            
            TimelineCacheManager.shared.saveSnapshot(
                feed: feed,
                listId: feed == .list ? listId : nil,
                tweets: updated,
                topCursor: topCursor(for: feed, listId: listId),
                bottomCursor: bottomCursor(for: feed, listId: listId)
            )
            prefetchMedia(for: olderOnes)
            
        case .failure(let err):
            pagingLogger.notice("paging \(feed.rawValue, privacy: .public) failed: \(err.localizedDescription, privacy: .public)")
            setPagingState(.failed, for: key)
            paging[key, default: Paging()].failures += 1
            // One more attempt on its own; after that the footer's retry is the way back, so a server that keeps
            // refusing is not asked again by scrolling into the same page.
            if paging[key]?.failures ?? 0 < 2 { scheduleRetry(for: key) }
        }
        
        // The next page, if the reader is still within reach of the bottom, without waiting for a scroll that will
        // not come: the page grew the content below them instead of moving the viewport.
        ListLoadMoreWatcher.shared.reevaluate()
    }
    
    private func scheduleRetry(for key: PagingKey) {
        guard paging[key]?.retry == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.paging[key]?.retry = nil
            self.loadMore(isScrollTriggered: false)
        }
        paging[key, default: Paging()].retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    
    // A chain that has just been built from its first page starts over
    private func resetPaging(for key: PagingKey) {
        paging[key]?.retry?.cancel()
        paging[key] = Paging()
        setPagingState(.idle, for: key)
    }
    
    private func currentFeedTweets(_ feed: HomeFeedType, listId: String) -> [Tweet] {
        switch feed {
        case .forYou: return forYouTweets
        case .following: return followingTweets
        case .bookmarks: return bookmarkTweets
        case .list: return listTweets[listId] ?? []
        }
    }
    
    private func setFeedTweets(_ list: [Tweet], for feed: HomeFeedType, listId: String) {
        switch feed {
        case .forYou:
            forYouTweets = list
        case .following:
            followingTweets = list
        case .bookmarks:
            bookmarkTweets = list
        case .list:
            listTweets[listId] = list
        }
    }
    
    // MARK: - Tweet Mutation & Cross-Feed Synchronization
    
    /// Shows a long post's whole text, or its shortened text again, in every copy of it on screen. Lists animate the row
    /// to its new height; the Home table animates it itself.
    func setTextExpanded(_ expanded: Bool, for tweet: Tweet) {
        withAnimation(.easeInOut(duration: 0.28)) {
            mutateTweet(id: tweet.canonicalId) { $0.setTextExpanded(expanded) }
        }
    }
    
    // `id` is a post's canonicalId, so a repost row and the post itself change together
    func mutateTweet(id: String, transform: (inout Tweet) -> Void) {
        // 1. Mutate in For You
        if let idx = forYouTweets.firstIndex(where: { $0.canonicalId == id }) {
            transform(&forYouTweets[idx])
        }
        // 2. Mutate in Following
        if let idx = followingTweets.firstIndex(where: { $0.canonicalId == id }) {
            transform(&followingTweets[idx])
        }
        if let idx = bookmarkTweets.firstIndex(where: { $0.canonicalId == id }) {
            transform(&bookmarkTweets[idx])
        }
        // 3. Mutate in Lists
        for (listId, list) in listTweets {
            if let idx = list.firstIndex(where: { $0.canonicalId == id }) {
                var copy = list
                transform(&copy[idx])
                listTweets[listId] = copy
            }
        }
        // 4. Mutate in active displayed list
        if let idx = tweets.firstIndex(where: { $0.canonicalId == id }) {
            transform(&tweets[idx])
        }
        // 5. Mutate on open profile pages
        TweetMutationHub.shared.apply(id: id, transform: transform)
    }
    
    /// Takes a deleted post, and reposts of it, off every feed and every open page
    func removePost(id: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            let matches: (Tweet) -> Bool = { $0.isCopy(ofPost: id) }
            forYouTweets.removeAll(where: matches)
            followingTweets.removeAll(where: matches)
            bookmarkTweets.removeAll(where: matches)
            for (listId, list) in listTweets {
                listTweets[listId] = list.filter { !matches($0) }
            }
            tweets.removeAll(where: matches)
        }
        TweetMutationHub.shared.remove(id: id)
    }
    
    /// Removes all tweets from a blocked or muted author across all timeline feeds
    func removeTweets(byAuthorId authorId: String, screenName: String? = nil) {
        withAnimation(.easeInOut(duration: 0.25)) {
            let matches: (Tweet) -> Bool = { t in
                (!authorId.isEmpty && t.author.id == authorId) ||
                (screenName != nil && !screenName!.isEmpty && t.author.screenName.caseInsensitiveCompare(screenName!) == .orderedSame)
            }
            forYouTweets.removeAll(where: matches)
            followingTweets.removeAll(where: matches)
            bookmarkTweets.removeAll(where: matches)
            for (listId, list) in listTweets {
                listTweets[listId] = list.filter { !matches($0) }
            }
            tweets.removeAll(where: matches)
        }
    }
    
    // MARK: - Bookmarks Feed

    // Where posts taken out of Bookmarks were, so a refused un-bookmark can put them back in their place
    @ObservationIgnored private var removedBookmarks: [String: (tweet: Tweet, index: Int)] = [:]

    // Called as soon as a post is bookmarked or un-bookmarked, from any screen, and again with the opposite value if X
    // refuses. Un-bookmarking takes the post out of Bookmarks at once, as X's own page does; bookmarking puts it at the
    // top. A refresh of the feed replaces all of this with X's own list anyway.
    func bookmarkStateChanged(postId: String, isBookmarked: Bool) {
        if isBookmarked {
            guard !bookmarkTweets.contains(where: { $0.canonicalId == postId }) else { return }
            let removed = removedBookmarks.removeValue(forKey: postId)
            guard var tweet = removed?.tweet ?? onScreenCopy(of: postId) else { return }
            tweet.isBookmarked = true
            bookmarkTweets.insert(tweet, at: min(removed?.index ?? 0, bookmarkTweets.count))
        } else {
            guard let index = bookmarkTweets.firstIndex(where: { $0.canonicalId == postId }) else { return }
            removedBookmarks[postId] = (bookmarkTweets[index], index)
            bookmarkTweets.remove(at: index)
        }
        if selectedFeed == .bookmarks { updateActiveTweets() }
        TimelineCacheManager.shared.saveSnapshot(feed: .bookmarks, tweets: bookmarkTweets,
                                                 topCursor: bookmarksTopCursor, bottomCursor: bookmarksBottomCursor)
    }

    // The freshest copy of a post the timeline holds, for adding it to Bookmarks
    private func onScreenCopy(of postId: String) -> Tweet? {
        let match: (Tweet) -> Bool = { $0.canonicalId == postId }
        return tweets.first(where: match) ?? forYouTweets.first(where: match) ?? followingTweets.first(where: match)
            ?? listTweets.values.lazy.compactMap { $0.first(where: match) }.first
            ?? TweetMutationHub.shared.copy(of: postId)
    }

    // MARK: - Optimistic Engagement Actions
    
    func toggleLike(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let postId = tweet.canonicalId
        let willFavorite = !tweet.isFavorited
        
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        
        mutateTweet(id: postId) { t in
            t.isFavorited = willFavorite
            t.favoriteCount = max(0, t.favoriteCount + (willFavorite ? 1 : -1))
        }
        
        let settle: (Result<Void, APIError>) -> Void = {
            EngagementGuard.settle($0, kind: .like, turnedOn: willFavorite, postId: postId)
        }
        if willFavorite {
            APIClient.shared.favoriteTweet(id: tweetId, completion: settle)
        } else {
            APIClient.shared.unfavoriteTweet(id: tweetId, completion: settle)
        }
    }
    
    func toggleRetweet(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let postId = tweet.canonicalId
        let willRetweet = !tweet.isRetweeted
        
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        
        mutateTweet(id: postId) { t in
            t.isRetweeted = willRetweet
            t.retweetCount = max(0, t.retweetCount + (willRetweet ? 1 : -1))
        }
        
        let settle: (Result<Void, APIError>) -> Void = {
            EngagementGuard.settle($0, kind: .repost, turnedOn: willRetweet, postId: postId)
        }
        if willRetweet {
            APIClient.shared.retweet(id: tweetId, completion: settle)
        } else {
            APIClient.shared.unretweet(id: tweetId, completion: settle)
        }
    }
    
    func toggleBookmark(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let postId = tweet.canonicalId
        let willBookmark = !tweet.isBookmarked
        
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        
        mutateTweet(id: postId) { t in
            t.isBookmarked = willBookmark
            t.bookmarkCount = max(0, t.bookmarkCount + (willBookmark ? 1 : -1))
        }
        bookmarkStateChanged(postId: postId, isBookmarked: willBookmark)
        
        let settle: (Result<Void, APIError>) -> Void = {
            EngagementGuard.settle($0, kind: .bookmark, turnedOn: willBookmark, postId: postId)
        }
        if willBookmark {
            APIClient.shared.bookmark(id: tweetId, completion: settle)
        } else {
            APIClient.shared.unbookmark(id: tweetId, completion: settle)
        }
    }
    
    func postReply(to tweet: Tweet, text: String, mediaIds: [String] = [], cardUri: String? = nil, completion: @escaping (Result<String, APIError>) -> Void) {
        let tweetId = tweet.id
        let postId = tweet.canonicalId
        
        mutateTweet(id: postId) { t in
            t.replyCount += 1
        }
        
        APIClient.shared.reply(to: tweetId, text: text, mediaIds: mediaIds, cardUri: cardUri) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let newTweetId):
                    completion(.success(newTweetId))
                case .failure(let error):
                    self.mutateTweet(id: postId) { t in
                        t.replyCount = max(0, t.replyCount - 1)
                    }
                    self.errorMessage = error.localizedDescription
                    EngagementGuard.reportFailure(error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    func postTweet(
        text: String,
        quoting tweet: Tweet? = nil,
        mediaIds: [String] = [],
        cardUri: String? = nil,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        let attachmentUrl = tweet.map { "https://x.com/\($0.author.screenName)/status/\($0.id)" }
        
        if let quotingTweet = tweet {
            mutateTweet(id: quotingTweet.canonicalId) { t in
                t.retweetCount += 1
            }
        }
        
        APIClient.shared.createTweet(text: text, attachmentUrl: attachmentUrl, mediaIds: mediaIds, cardUri: cardUri) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let newTweetId):
                    completion(.success(newTweetId))
                case .failure(let error):
                    if let quotingTweet = tweet {
                        self.mutateTweet(id: quotingTweet.canonicalId) { t in
                            t.retweetCount = max(0, t.retweetCount - 1)
                        }
                    }
                    self.errorMessage = error.localizedDescription
                    EngagementGuard.reportFailure(error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func prefetchMedia(for tweetsList: [Tweet]) {
        let tweets = Array(tweetsList.prefix(60))
        let cache = MediaCacheManager.shared
        DispatchQueue.global(qos: .utility).async {
            cache.prefetchTweetsMedia(tweets)
        }
    }
}
