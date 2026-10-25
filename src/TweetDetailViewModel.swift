//
//  TweetDetailViewModel.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit
import Combine

final class TweetDetailViewModel: ObservableObject {
    @Published var focalTweet: Tweet
    @Published var ancestors: [Tweet] = []
    @Published var replies: [Tweet] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var error: String? = nil
    @Published var bottomCursor: String? = nil
    
    // Quick reply input text state
    @Published var quickReplyText: String = ""
    @Published var isSubmittingReply: Bool = false
    
    private let apiClient: APIClient
    
    init(focalTweet: Tweet, apiClient: APIClient = .shared) {
        self.focalTweet = focalTweet
        self.apiClient = apiClient
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MaX_PromotedPostsSettingDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !ThemeManager.shared.showPromotedPosts {
                self.replies.removeAll { $0.isPromoted }
                self.ancestors.removeAll { $0.isPromoted }
            } else {
                self.loadDetail()
            }
        }
    }
    
    // MARK: - Load Tweet Detail & Conversation Thread
    func loadDetail() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        
        apiClient.fetchTweetDetail(tweetId: focalTweet.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let data):
                    if let freshFocal = data.focalTweet {
                        self.focalTweet = freshFocal
                    }
                    self.ancestors = data.ancestors
                    self.replies = data.replies
                    self.bottomCursor = data.bottomCursor
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Load More Replies (Pagination)
    func loadMoreReplies() {
        guard let cursor = bottomCursor, !cursor.isEmpty, !isLoadingMore else { return }
        isLoadingMore = true
        
        apiClient.fetchTweetDetail(tweetId: focalTweet.id, cursor: cursor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingMore = false
                switch result {
                case .success(let data):
                    // Append new unique replies
                    var existingIds = Set(self.replies.map { $0.id })
                    for r in data.replies where !existingIds.contains(r.id) {
                        self.replies.append(r)
                        existingIds.insert(r.id)
                    }
                    self.bottomCursor = data.bottomCursor
                case .failure:
                    break
                }
            }
        }
    }
    
    // MARK: - Post Quick Reply
    func postQuickReply(completion: ((Bool) -> Void)? = nil) {
        let trimmed = quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSubmittingReply else { return }
        guard EngagementGuard.allows(focalTweet) else { return }
        
        isSubmittingReply = true
        let textToSend = trimmed
        self.quickReplyText = "" // clear optimistic
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        apiClient.reply(to: focalTweet.id, text: textToSend) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSubmittingReply = false
                switch result {
                case .success(let newTweetId):
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    self.focalTweet.replyCount += 1
                    
                    // Create local synthetic tweet to immediately show in replies list
                    let myUser = TweetUser(
                        id: "me",
                        name: "You",
                        screenName: "user",
                        avatarUrl: nil,
                        isVerified: false
                    )
                    let newTweet = Tweet(
                        id: newTweetId,
                        text: textToSend,
                        createdAt: Date(),
                        author: myUser,
                        media: [],
                        replyCount: 0,
                        retweetCount: 0,
                        favoriteCount: 0,
                        isRetweet: false,
                        retweetedBy: nil,
                        isFavorited: false,
                        isRetweeted: false,
                        isBookmarked: false,
                        bookmarkCount: 0
                    )
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.replies.insert(newTweet, at: 0)
                    }
                    completion?(true)
                case .failure(let error):
                    // Restore text on failure
                    self.quickReplyText = textToSend
                    EngagementGuard.reportFailure(error)
                    completion?(false)
                }
            }
        }
    }
    
    // MARK: - Mutate Any Tweet in Focal/Ancestors/Replies
    private func mutateTweet(id: String, transform: (inout Tweet) -> Void) {
        if focalTweet.id == id {
            transform(&focalTweet)
        }
        for i in 0..<ancestors.count {
            if ancestors[i].id == id {
                transform(&ancestors[i])
            }
        }
        for i in 0..<replies.count {
            if replies[i].id == id {
                transform(&replies[i])
            }
        }
        // Also sync back to global timeline view model
        TimelineViewModel.shared.mutateTweet(id: id, transform: transform)
    }
    
    // MARK: - Optimistic Like Toggle
    func toggleLike(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let wasLiked = tweet.isFavorited
        let willLike = !wasLiked
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        mutateTweet(id: tweetId) { t in
            t.isFavorited = willLike
            t.favoriteCount = max(0, t.favoriteCount + (willLike ? 1 : -1))
        }
        
        if willLike {
            apiClient.favoriteTweet(id: tweetId) { [weak self] res in
                if case .failure(let err) = res {
                    EngagementGuard.reportFailure(err)
                    DispatchQueue.main.async {
                        self?.mutateTweet(id: tweetId) { t in
                            t.isFavorited = false
                            t.favoriteCount = max(0, t.favoriteCount - 1)
                        }
                    }
                }
            }
        } else {
            apiClient.unfavoriteTweet(id: tweetId) { [weak self] res in
                if case .failure(let err) = res {
                    EngagementGuard.reportFailure(err)
                    DispatchQueue.main.async {
                        self?.mutateTweet(id: tweetId) { t in
                            t.isFavorited = true
                            t.favoriteCount += 1
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Optimistic Retweet Toggle
    func toggleRetweet(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let wasRetweeted = tweet.isRetweeted
        let willRetweet = !wasRetweeted
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        mutateTweet(id: tweetId) { t in
            t.isRetweeted = willRetweet
            t.retweetCount = max(0, t.retweetCount + (willRetweet ? 1 : -1))
        }
        
        if willRetweet {
            apiClient.retweet(id: tweetId) { [weak self] res in
                if case .failure(let err) = res {
                    EngagementGuard.reportFailure(err)
                    DispatchQueue.main.async {
                        self?.mutateTweet(id: tweetId) { t in
                            t.isRetweeted = false
                            t.retweetCount = max(0, t.retweetCount - 1)
                        }
                    }
                }
            }
        } else {
            apiClient.unretweet(id: tweetId) { [weak self] res in
                if case .failure(let err) = res {
                    EngagementGuard.reportFailure(err)
                    DispatchQueue.main.async {
                        self?.mutateTweet(id: tweetId) { t in
                            t.isRetweeted = true
                            t.retweetCount += 1
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Optimistic Bookmark Toggle
    func toggleBookmark(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let wasBookmarked = tweet.isBookmarked
        let willBookmark = !wasBookmarked
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        mutateTweet(id: tweetId) { t in
            t.isBookmarked = willBookmark
            t.bookmarkCount = max(0, t.bookmarkCount + (willBookmark ? 1 : -1))
        }
        
        if willBookmark {
            apiClient.bookmark(id: tweetId) { [weak self] res in
                if case .failure(let err) = res {
                    EngagementGuard.reportFailure(err)
                    DispatchQueue.main.async {
                        self?.mutateTweet(id: tweetId) { t in
                            t.isBookmarked = false
                            t.bookmarkCount = max(0, t.bookmarkCount - 1)
                        }
                    }
                }
            }
        } else {
            apiClient.unbookmark(id: tweetId) { [weak self] res in
                if case .failure(let err) = res {
                    EngagementGuard.reportFailure(err)
                    DispatchQueue.main.async {
                        self?.mutateTweet(id: tweetId) { t in
                            t.isBookmarked = true
                            t.bookmarkCount += 1
                        }
                    }
                }
            }
        }
    }
}
