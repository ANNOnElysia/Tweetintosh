//
//  TimelineViewModel.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import Combine

final class TimelineViewModel: ObservableObject {
    @Published var tweets: [Tweet] = []
    
    @Published var isLoadingInitial = true
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private var topCursor: String?
    private var bottomCursor: String?
    private var timer: Timer?
    
    init() {
        checkAuth()
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
        // 1. Immediately load local cache for instantaneous 0ms display
        if let cached = TimelineCacheManager.shared.loadCachedSnapshot(), !cached.tweets.isEmpty {
            self.tweets = cached.tweets
            self.topCursor = cached.topCursor
            self.bottomCursor = cached.bottomCursor
            self.isLoadingInitial = false
            prefetchMedia(for: cached.tweets)
        }
        
        // 2. Fetch fresh posts from GraphQL API
        refresh(silently: !tweets.isEmpty)
        
        // 3. Start background poll timer (every 75 seconds)
        startPollTimer()
    }
    
    // MARK: - Refresh (Pull or Initial)
    func refresh(silently: Bool = false) {
        if !silently {
            isRefreshing = true
        }
        
        let startTime = Date()
        APIClient.shared.fetchHomeTimeline(cursor: nil) { [weak self] result in
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
                    if self.tweets.isEmpty {
                        // First load
                        self.tweets = payload.tweets
                        self.topCursor = payload.topCursor
                        self.bottomCursor = payload.bottomCursor
                        TimelineCacheManager.shared.saveSnapshot(
                            tweets: self.tweets,
                            topCursor: self.topCursor,
                            bottomCursor: self.bottomCursor
                        )
                        self.prefetchMedia(for: self.tweets)
                    } else {
                        // Incremental diff: find tweets not already in list
                        let existingIds = Set(self.tweets.map { $0.id })
                        let newOnes = payload.tweets.filter { !existingIds.contains($0.id) }
                        
                        if !newOnes.isEmpty {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                                self.tweets.insert(contentsOf: newOnes, at: 0)
                            }
                            if let newTop = payload.topCursor {
                                self.topCursor = newTop
                            }
                            TimelineCacheManager.shared.saveSnapshot(
                                tweets: self.tweets,
                                topCursor: self.topCursor,
                                bottomCursor: self.bottomCursor
                            )
                            self.prefetchMedia(for: newOnes)
                        }
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
        
        APIClient.shared.fetchHomeTimeline(cursor: cursor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingMore = false
                
                switch result {
                case .success(let payload):
                    let existingIds = Set(self.tweets.map { $0.id })
                    let olderOnes = payload.tweets.filter { !existingIds.contains($0.id) }
                    
                    self.tweets.append(contentsOf: olderOnes)
                    self.bottomCursor = payload.bottomCursor
                    
                    TimelineCacheManager.shared.saveSnapshot(
                        tweets: self.tweets,
                        topCursor: self.topCursor,
                        bottomCursor: self.bottomCursor
                    )
                    
                case .failure(let err):
                    print("Failed to load more: \(err.localizedDescription)")
                }
            }
        }
    }
    
    private func startPollTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 75.0, repeats: true) { [weak self] _ in
            self?.checkNewPostsSilently()
        }
    }
    
    private func checkNewPostsSilently() {
        guard isAuthenticated, !tweets.isEmpty else { return }
        
        APIClient.shared.fetchHomeTimeline(cursor: topCursor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if case .success(let payload) = result {
                    let existingIds = Set(self.tweets.map { $0.id })
                    let fresh = payload.tweets.filter { !existingIds.contains($0.id) }
                    if !fresh.isEmpty {
                        withAnimation(.spring()) {
                            self.tweets.insert(contentsOf: fresh, at: 0)
                        }
                    }
                }
            }
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
    
    deinit {
        timer?.invalidate()
    }
}
