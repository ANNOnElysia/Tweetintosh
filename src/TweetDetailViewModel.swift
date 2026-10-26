//
//  TweetDetailViewModel.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import os

private let detailLogger = Logger(subsystem: "com.anno.tweetintosh", category: "preload")
import AppKit
import Combine

final class TweetDetailViewModel: ObservableObject {
    @Published var focalTweet: Tweet
    @Published var ancestors: [Tweet] = []
    @Published var replies: [Tweet] = [] {
        didSet { debugDumpReplies() } // TEMP(reply-debug)
    }
    
    // TEMP(reply-debug)
    private func debugDumpReplies() {
        guard ProcessInfo.processInfo.environment["MAX_DEBUG_DETAIL"] != nil else { return }
        let log = Logger(subsystem: "com.anno.tweetintosh", category: "replydebug")
        let authorId = focalTweet.author.id
        log.notice("focal=\(self.focalTweet.id, privacy: .public) author=\(authorId, privacy: .public) replies=\(self.replies.count, privacy: .public)")
        for (i, r) in replies.enumerated() {
            log.notice("#\(i, privacy: .public) id=\(r.id, privacy: .public) parent=\(r.inReplyToStatusId ?? "-", privacy: .public) by=\(r.author.screenName, privacy: .public)\(r.author.id == authorId ? "(AUTHOR)" : "", privacy: .public) replyCount=\(r.replyCount, privacy: .public)")
        }
        for (t, thread) in replyThreads.enumerated() {
            log.notice("thread \(t, privacy: .public): \(thread.map { $0.id.suffix(5) }.joined(separator: ","), privacy: .public)")
        }
    }
    
    // Replies grouped into conversations by who they answer, wherever X happens to list them: each reply to the
    // post (or to something that isn't loaded) starts one, and every reply that answers a reply in it, directly or
    // further down, belongs to it. Within a conversation the replies keep the order X sent them in.
    var replyThreads: [[Tweet]] {
        let byId = Dictionary(replies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rootOf: [String: String] = [:]
        func root(of tweet: Tweet, visiting: Set<String>) -> String {
            if let known = rootOf[tweet.id] { return known }
            var result = tweet.id
            if let parentId = tweet.inReplyToStatusId, parentId != focalTweet.id,
               let parent = byId[parentId], !visiting.contains(parentId) {
                result = root(of: parent, visiting: visiting.union([tweet.id]))
            }
            rootOf[tweet.id] = result
            return result
        }
        var order: [String] = []
        var threads: [String: [Tweet]] = [:]
        for reply in replies {
            let rootId = root(of: reply, visiting: [])
            if threads[rootId] == nil { order.append(rootId) }
            threads[rootId, default: []].append(reply)
        }
        // Root first, then each reply directly after the one it answers (replies to the same parent keep X's order)
        return order.compactMap { rootId -> [Tweet]? in
            guard let members = threads[rootId], let rootTweet = byId[rootId] else { return threads[rootId] }
            var children: [String: [Tweet]] = [:]
            for member in members where member.id != rootId {
                if let parentId = member.inReplyToStatusId { children[parentId, default: []].append(member) }
            }
            var ordered: [Tweet] = []
            var placed = Set<String>()
            func place(_ tweet: Tweet) {
                guard placed.insert(tweet.id).inserted else { return }
                ordered.append(tweet)
                for child in children[tweet.id] ?? [] { place(child) }
            }
            place(rootTweet)
            for member in members { place(member) }   // anything that didn't hang off the tree
            return ordered
        }
    }
    
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
            forName: NSNotification.Name("Tweetintosh_PromotedPostsSettingDidChange"),
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
    private func applyDetail(_ data: TweetDetailPrefetcher.Detail) {
        if let freshFocal = data.focalTweet {
            focalTweet = freshFocal
        }
        ancestors = data.ancestors
        replies = data.replies
        bottomCursor = data.bottomCursor
    }
    
    func loadDetail() {
        guard !isLoading else { return }
        
        // A detail page warmed by hovering opens already filled in; it is only refetched if it has gone stale
        var hasCached = false
        if let cached = TweetDetailPrefetcher.shared.cached(focalTweet.id) {
            detailLogger.notice("detail opened from prefetch cache \(self.focalTweet.id, privacy: .public)")
            applyDetail(cached.detail)
            hasCached = true
            if Date().timeIntervalSince(cached.fetchedAt) < 30 { return }
        }
        if !hasCached { isLoading = true }
        error = nil
        
        apiClient.fetchTweetDetail(tweetId: focalTweet.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let data):
                    self.applyDetail(data)
                case .failure(let err):
                    if !hasCached { self.error = err.localizedDescription }
                }
            }
        }
    }
    
    // X lists only the first replies of each conversation. This fetches the replies to one of them (for "Show
    // replies") and adds the new ones to the list, where they group under the reply they answer.
    func loadSubReplies(of tweet: Tweet, completion: @escaping () -> Void) {
        apiClient.fetchTweetDetail(tweetId: tweet.id) { [weak self] result in
            DispatchQueue.main.async {
                defer { completion() }
                guard let self = self, case .success(let data) = result else { return }
                var existing = Set(self.replies.map { $0.id })
                for reply in data.replies where !existing.contains(reply.id) && !reply.isPromoted {
                    self.replies.append(reply)
                    existing.insert(reply.id)
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
                    var added = 0
                    for r in data.replies where !existingIds.contains(r.id) {
                        self.replies.append(r)
                        existingIds.insert(r.id)
                        added += 1
                    }
                    // X keeps handing back a cursor even when the replies have run out; stop paging (and the
                    // spinner) once a page brings nothing new
                    self.bottomCursor = (added == 0 || data.bottomCursor == cursor) ? nil : data.bottomCursor
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
