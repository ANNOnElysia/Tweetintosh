//
//  TimelineViewModel.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
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
        fetchUserLists()
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
            let remainingDelay = max(0.0, 1.2 - elapsed)
            
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
                        if isUserInitiated {
                            // User intentionally pulled down to refresh: prepend new ones immediately!
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
                            // Auto-fetch / Background refresh:
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
    
    private func prefetchMedia(for tweetsList: [Tweet]) {
        var urlsToFetch: [String] = []
        for tweet in tweetsList.prefix(15) {
            if let avatar = tweet.author.avatarUrl {
                urlsToFetch.append(avatar)
            }
            for media in tweet.media {
                if media.mediaUrl.contains("pbs.twimg.com/media") && !media.mediaUrl.contains("?") {
                    urlsToFetch.append("\(media.mediaUrl)?format=jpg&name=medium")
                } else {
                    urlsToFetch.append(media.mediaUrl)
                }
            }
        }
        ImageCache.shared.prefetch(urls: urlsToFetch)
    }
}
