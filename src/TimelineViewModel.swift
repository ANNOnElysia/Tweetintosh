//
//  TimelineViewModel.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import os

private let pollLogger = Logger(subsystem: "com.antigravity.max", category: "preload")
import Combine

final class TimelineViewModel: ObservableObject {
    static let shared = TimelineViewModel()
    
    @Published var selectedFeed: HomeFeedType = .forYou {
        didSet {
            updateActiveTweets()
        }
    }
    
    @Published var tweets: [Tweet] = []
    
    // Official Twitter Lists for authenticated account
    @Published var userLists: [TwitterList] = []
    @Published var selectedListId: String = ""
    @Published var isLoadingLists: Bool = false
    
    var selectedList: TwitterList? {
        userLists.first { $0.id == selectedListId } ?? userLists.first
    }
    
    // Independent storage for each feed
    @Published var forYouTweets: [Tweet] = []
    @Published var followingTweets: [Tweet] = []
    @Published var listTweets: [String: [Tweet]] = [:]
    
    // Pending new tweets buffer (holds background/auto-fetched tweets so user reading is never disrupted or pushed down)
    @Published var forYouPendingTweets: [Tweet] = []
    @Published var followingPendingTweets: [Tweet] = []
    @Published var listPendingTweets: [String: [Tweet]] = [:]
    
    @Published var isLoadingInitial = true
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private var forYouTopCursor: String?
    private var forYouBottomCursor: String?
    
    private var followingTopCursor: String?
    private var followingBottomCursor: String?
    
    private var listTopCursors: [String: String] = [:]
    private var listBottomCursors: [String: String] = [:]
    
    // Track seen tweet IDs for the algorithmic "For You" feed
    private var seenTweetIds: [String] = []
    
    var topCursor: String? {
        get {
            switch selectedFeed {
            case .forYou: return forYouTopCursor
            case .following: return followingTopCursor
            case .list: return listTopCursors[selectedListId]
            }
        }
        set {
            switch selectedFeed {
            case .forYou: forYouTopCursor = newValue
            case .following: followingTopCursor = newValue
            case .list: listTopCursors[selectedListId] = newValue
            }
        }
    }
    
    var bottomCursor: String? {
        get {
            switch selectedFeed {
            case .forYou: return forYouBottomCursor
            case .following: return followingBottomCursor
            case .list: return listBottomCursors[selectedListId]
            }
        }
        set {
            switch selectedFeed {
            case .forYou: forYouBottomCursor = newValue
            case .following: followingBottomCursor = newValue
            case .list: listBottomCursors[selectedListId] = newValue
            }
        }
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
            forName: NSNotification.Name("MaX_PromotedPostsSettingDidChange"),
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
    private var pollTimer: Timer?
    private var lastFetchAt = Date()
    
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
        }
        
        if let cachedFollowing = TimelineCacheManager.shared.loadCachedSnapshot(feed: .following), !cachedFollowing.tweets.isEmpty {
            self.followingTweets = cachedFollowing.tweets
            self.followingTopCursor = cachedFollowing.topCursor
            self.followingBottomCursor = cachedFollowing.bottomCursor
            self.prefetchMedia(for: cachedFollowing.tweets)
        }
        
        if let cachedList = TimelineCacheManager.shared.loadCachedSnapshot(feed: .list, listId: selectedListId), !cachedList.tweets.isEmpty {
            self.listTweets[selectedListId] = cachedList.tweets
            self.listTopCursors[selectedListId] = cachedList.topCursor
            self.listBottomCursors[selectedListId] = cachedList.bottomCursor
            self.prefetchMedia(for: cachedList.tweets)
        }
        
        updateActiveTweets()
        if !tweets.isEmpty {
            self.isLoadingInitial = false
        }
        
        // 2. Fetch fresh posts from GraphQL API (Fetch once on launch/restart)
        refresh(silently: !tweets.isEmpty, isUserInitiated: false)
    }
    
    private func updateActiveTweets() {
        switch selectedFeed {
        case .forYou:
            self.tweets = forYouTweets
        case .following:
            self.tweets = followingTweets
        case .list:
            self.tweets = listTweets[selectedListId] ?? []
        }
    }
    
    func pendingCount(for feed: HomeFeedType) -> Int {
        switch feed {
        case .forYou: return forYouPendingTweets.count
        case .following: return followingPendingTweets.count
        case .list: return listPendingTweets[selectedListId]?.count ?? 0
        }
    }
    
    func enqueuePendingTweets(_ newTweets: [Tweet], for feed: HomeFeedType) {
        switch feed {
        case .forYou:
            let existingPendingIds = Set(forYouPendingTweets.map { $0.id })
            let trulyNew = newTweets.filter { !existingPendingIds.contains($0.id) }
            forYouPendingTweets.insert(contentsOf: trulyNew, at: 0)
        case .following:
            let existingPendingIds = Set(followingPendingTweets.map { $0.id })
            let trulyNew = newTweets.filter { !existingPendingIds.contains($0.id) }
            followingPendingTweets.insert(contentsOf: trulyNew, at: 0)
        case .list:
            var currentPending = listPendingTweets[selectedListId] ?? []
            let existingPendingIds = Set(currentPending.map { $0.id })
            let trulyNew = newTweets.filter { !existingPendingIds.contains($0.id) }
            currentPending.insert(contentsOf: trulyNew, at: 0)
            listPendingTweets[selectedListId] = currentPending
        }
    }
    
    func applyPendingTweets(for feed: HomeFeedType) {
        let pending: [Tweet]
        switch feed {
        case .forYou: pending = forYouPendingTweets
        case .following: pending = followingPendingTweets
        case .list: pending = listPendingTweets[selectedListId] ?? []
        }
        guard !pending.isEmpty else { return }
        
        var updated = self.currentFeedTweets(feed)
        updated.insert(contentsOf: pending, at: 0)
        self.setFeedTweets(updated, for: feed)
        
        switch feed {
        case .forYou:
            forYouPendingTweets = []
            let newIds = pending.map { $0.id }
            self.seenTweetIds = Array(Set(newIds + self.seenTweetIds).prefix(60))
        case .following:
            followingPendingTweets = []
        case .list:
            listPendingTweets[selectedListId] = []
        }
        
        TimelineCacheManager.shared.saveSnapshot(
            feed: feed,
            listId: (feed == .list) ? selectedListId : nil,
            tweets: updated,
            topCursor: self.topCursor,
            bottomCursor: self.bottomCursor
        )
        
        if selectedFeed == feed {
            updateActiveTweets()
            TimelineScrollCoordinator.shared.unreadCountAbove = 0
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
        }
    }
    
    func nextFeed() {
        let all: [HomeFeedType] = userLists.isEmpty ? [.forYou, .following] : HomeFeedType.allCases
        if let idx = all.firstIndex(of: selectedFeed) {
            let nextIdx = (idx + 1) % all.count
            selectFeed(all[nextIdx])
        }
    }
    
    func prevFeed() {
        let all: [HomeFeedType] = userLists.isEmpty ? [.forYou, .following] : HomeFeedType.allCases
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
        let seenIdsToSend = (currentFeed == .forYou) ? seenTweetIds : []
        let startTime = Date()
        
        APIClient.shared.fetchGraphQLHomeTimeline(
            feedType: currentFeed,
            cursor: nil,
            seenTweetIds: seenIdsToSend
        ) { [weak self] result in
            let elapsed = Date().timeIntervalSince(startTime)
            let minDisplayDuration: Double = isUserInitiated ? 2.4 : 1.2
            let remainingDelay = max(0.0, minDisplayDuration - elapsed)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + (silently ? 0 : remainingDelay)) {
                guard let self = self else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    self.isRefreshing = false
                    self.isLoadingInitial = false
                }
                
                switch result {
                case .success(let payload):
                    self.errorMessage = nil
                    let existingIds = Set(self.currentFeedTweets(currentFeed).map { $0.id })
                    let newOnes = payload.tweets.filter { !existingIds.contains($0.id) }
                    
                    if self.currentFeedTweets(currentFeed).isEmpty {
                        // First load for this feed
                        self.setFeedTweets(payload.tweets, for: currentFeed)
                        if currentFeed == .forYou {
                            self.forYouTopCursor = payload.topCursor
                            self.forYouBottomCursor = payload.bottomCursor
                            self.seenTweetIds = Array(payload.tweets.prefix(40).map { $0.id })
                        } else if currentFeed == .following {
                            self.followingTopCursor = payload.topCursor
                            self.followingBottomCursor = payload.bottomCursor
                        } else {
                            self.listTopCursors[self.selectedListId] = payload.topCursor
                            self.listBottomCursors[self.selectedListId] = payload.bottomCursor
                        }
                        
                        TimelineCacheManager.shared.saveSnapshot(
                            feed: currentFeed,
                            listId: (currentFeed == .list) ? self.selectedListId : nil,
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
                            var updated = self.currentFeedTweets(currentFeed)
                            updated.insert(contentsOf: newOnes, at: 0)
                            self.setFeedTweets(updated, for: currentFeed)
                            
                            if currentFeed == .forYou {
                                if let newTop = payload.topCursor {
                                    self.forYouTopCursor = newTop
                                }
                                let newIds = newOnes.map { $0.id }
                                self.seenTweetIds = Array(Set(newIds + self.seenTweetIds).prefix(60))
                            } else if currentFeed == .following {
                                if let newTop = payload.topCursor {
                                    self.followingTopCursor = newTop
                                }
                            } else {
                                if let newTop = payload.topCursor {
                                    self.listTopCursors[self.selectedListId] = newTop
                                }
                            }
                            
                            TimelineCacheManager.shared.saveSnapshot(
                                feed: currentFeed,
                                listId: (currentFeed == .list) ? self.selectedListId : nil,
                                tweets: updated,
                                topCursor: self.topCursor,
                                bottomCursor: self.bottomCursor
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
                            self.enqueuePendingTweets(newOnes, for: currentFeed)
                            self.prefetchMedia(for: newOnes)
                            
                            if self.selectedFeed == currentFeed {
                                TimelineScrollCoordinator.shared.unreadCountAbove = self.pendingCount(for: currentFeed)
                            }
                        }
                    } else {
                        // When no new tweets arrive, only update cursors:
                        // NEVER overwrite existing tweets so the user's reading list is never blown away!
                        if currentFeed == .forYou {
                            if let newTop = payload.topCursor { self.forYouTopCursor = newTop }
                            if let newBottom = payload.bottomCursor { self.forYouBottomCursor = newBottom }
                        } else if currentFeed == .following {
                            if let newTop = payload.topCursor { self.followingTopCursor = newTop }
                            if let newBottom = payload.bottomCursor { self.followingBottomCursor = newBottom }
                        } else {
                            if let newTop = payload.topCursor { self.listTopCursors[self.selectedListId] = newTop }
                            if let newBottom = payload.bottomCursor { self.listBottomCursors[self.selectedListId] = newBottom }
                        }
                    }
                    
                    if self.selectedFeed == currentFeed {
                        self.updateActiveTweets()
                    }
                    
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
    func loadMore() {
        guard !isLoadingMore, let cursor = bottomCursor else { return }
        isLoadingMore = true
        let currentFeed = selectedFeed
        
        APIClient.shared.fetchGraphQLHomeTimeline(
            feedType: currentFeed,
            cursor: cursor,
            seenTweetIds: currentFeed == .forYou ? seenTweetIds : []
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingMore = false
                
                switch result {
                case .success(let payload):
                    let existingIds = Set(self.currentFeedTweets(currentFeed).map { $0.id })
                    let olderOnes = payload.tweets.filter { !existingIds.contains($0.id) }
                    
                    var updated = self.currentFeedTweets(currentFeed)
                    updated.append(contentsOf: olderOnes)
                    self.setFeedTweets(updated, for: currentFeed)
                    
                    if currentFeed == .forYou {
                        self.forYouBottomCursor = payload.bottomCursor
                    } else if currentFeed == .following {
                        self.followingBottomCursor = payload.bottomCursor
                    } else {
                        self.listBottomCursors[self.selectedListId] = payload.bottomCursor
                    }
                    
                    if self.selectedFeed == currentFeed {
                        self.updateActiveTweets()
                    }
                    
                    TimelineCacheManager.shared.saveSnapshot(
                        feed: currentFeed,
                        listId: (currentFeed == .list) ? self.selectedListId : nil,
                        tweets: updated,
                        topCursor: self.topCursor,
                        bottomCursor: self.bottomCursor
                    )
                    
                case .failure(let err):
                    print("Failed to load more: \(err.localizedDescription)")
                }
            }
        }
    }
    
    private func currentFeedTweets(_ feed: HomeFeedType) -> [Tweet] {
        switch feed {
        case .forYou: return forYouTweets
        case .following: return followingTweets
        case .list: return listTweets[selectedListId] ?? []
        }
    }
    
    private func setFeedTweets(_ list: [Tweet], for feed: HomeFeedType) {
        switch feed {
        case .forYou:
            forYouTweets = list
        case .following:
            followingTweets = list
        case .list:
            listTweets[selectedListId] = list
        }
    }
    
    // MARK: - Tweet Mutation & Cross-Feed Synchronization
    
    func mutateTweet(id: String, transform: (inout Tweet) -> Void) {
        // 1. Mutate in For You
        if let idx = forYouTweets.firstIndex(where: { $0.id == id }) {
            transform(&forYouTweets[idx])
        }
        // 2. Mutate in Following
        if let idx = followingTweets.firstIndex(where: { $0.id == id }) {
            transform(&followingTweets[idx])
        }
        // 3. Mutate in Lists
        for (listId, list) in listTweets {
            if let idx = list.firstIndex(where: { $0.id == id }) {
                var copy = list
                transform(&copy[idx])
                listTweets[listId] = copy
            }
        }
        // 4. Mutate in active displayed list
        if let idx = tweets.firstIndex(where: { $0.id == id }) {
            transform(&tweets[idx])
        }
        // 5. Mutate on open profile pages
        TweetMutationHub.shared.apply(id: id, transform: transform)
    }
    
    // MARK: - Optimistic Engagement Actions
    
    func toggleLike(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let willFavorite = !tweet.isFavorited
        
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        
        mutateTweet(id: tweetId) { t in
            t.isFavorited = willFavorite
            t.favoriteCount = max(0, t.favoriteCount + (willFavorite ? 1 : -1))
        }
        
        let completion: (Result<Void, APIError>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure(let error) = result {
                    // Rollback on failure
                    self.mutateTweet(id: tweetId) { t in
                        t.isFavorited = !willFavorite
                        t.favoriteCount = max(0, t.favoriteCount + (!willFavorite ? 1 : -1))
                    }
                    self.errorMessage = error.localizedDescription
                    EngagementGuard.reportFailure(error)
                }
            }
        }
        
        if willFavorite {
            APIClient.shared.favoriteTweet(id: tweetId, completion: completion)
        } else {
            APIClient.shared.unfavoriteTweet(id: tweetId, completion: completion)
        }
    }
    
    func toggleRetweet(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let willRetweet = !tweet.isRetweeted
        
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        
        mutateTweet(id: tweetId) { t in
            t.isRetweeted = willRetweet
            t.retweetCount = max(0, t.retweetCount + (willRetweet ? 1 : -1))
        }
        
        let completion: (Result<Void, APIError>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure(let error) = result {
                    self.mutateTweet(id: tweetId) { t in
                        t.isRetweeted = !willRetweet
                        t.retweetCount = max(0, t.retweetCount + (!willRetweet ? 1 : -1))
                    }
                    self.errorMessage = error.localizedDescription
                    EngagementGuard.reportFailure(error)
                }
            }
        }
        
        if willRetweet {
            APIClient.shared.retweet(id: tweetId, completion: completion)
        } else {
            APIClient.shared.unretweet(id: tweetId, completion: completion)
        }
    }
    
    func toggleBookmark(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let willBookmark = !tweet.isBookmarked
        
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        
        mutateTweet(id: tweetId) { t in
            t.isBookmarked = willBookmark
            t.bookmarkCount = max(0, t.bookmarkCount + (willBookmark ? 1 : -1))
        }
        
        let completion: (Result<Void, APIError>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .failure(let error) = result {
                    self.mutateTweet(id: tweetId) { t in
                        t.isBookmarked = !willBookmark
                        t.bookmarkCount = max(0, t.bookmarkCount + (!willBookmark ? 1 : -1))
                    }
                    self.errorMessage = error.localizedDescription
                    EngagementGuard.reportFailure(error)
                }
            }
        }
        
        if willBookmark {
            APIClient.shared.bookmark(id: tweetId, completion: completion)
        } else {
            APIClient.shared.unbookmark(id: tweetId, completion: completion)
        }
    }
    
    func postReply(to tweet: Tweet, text: String, completion: @escaping (Result<String, APIError>) -> Void) {
        let tweetId = tweet.id
        
        mutateTweet(id: tweetId) { t in
            t.replyCount += 1
        }
        
        APIClient.shared.reply(to: tweetId, text: text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let newTweetId):
                    completion(.success(newTweetId))
                case .failure(let error):
                    self.mutateTweet(id: tweetId) { t in
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
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        let attachmentUrl = tweet.map { "https://x.com/\($0.author.screenName)/status/\($0.id)" }
        
        if let quotingTweet = tweet {
            mutateTweet(id: quotingTweet.id) { t in
                t.retweetCount += 1
            }
        }
        
        APIClient.shared.createTweet(text: text, attachmentUrl: attachmentUrl) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let newTweetId):
                    completion(.success(newTweetId))
                case .failure(let error):
                    if let quotingTweet = tweet {
                        self.mutateTweet(id: quotingTweet.id) { t in
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
        MediaCacheManager.shared.prefetchTweetsMedia(tweetsList, maxTweets: 60)
    }
}
