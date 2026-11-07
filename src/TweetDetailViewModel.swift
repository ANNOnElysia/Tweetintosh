//
//  TweetDetailViewModel.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import os

private let detailLogger = Logger(subsystem: "com.anno.tweetintosh", category: "preload")
import AppKit
import Combine

final class TweetDetailViewModel: ObservableObject, TweetMutationTarget {
    @Published var focalTweet: Tweet
    @Published var ancestors: [Tweet] = []
    @Published var replies: [Tweet] = [] {
        didSet {
            replyThreads = groupedReplies()
            DebugSupport.repliesDidChange(focal: focalTweet, replies: replies, threads: replyThreads)
        }
    }
    // Worked out when the replies change, because the page reads it every time it redraws
    private(set) var replyThreads: [[Tweet]] = []
    
    // Replies grouped into conversations by who they answer, wherever X happens to list them: each reply to the
    // post (or to something that isn't loaded) starts one, and every reply that answers a reply in it, directly or
    // further down, belongs to it. Within a conversation the replies keep the order X sent them in.
    private func groupedReplies() -> [[Tweet]] {
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
    @Published var isRefreshing: Bool = false
    // Replies sent from here that X's answers may not include yet; they stay in the list until X lists them
    private var ownPendingReplies: [String: Tweet] = [:]
    @Published var isLoadingMore: Bool = false
    @Published var error: String? = nil
    @Published var bottomCursor: String? = nil
    
    // Quick reply input text state
    @Published var quickReplyText: String = ""
    @Published var isSubmittingReply: Bool = false
    
    private let apiClient: APIClient
    
    init(focalTweet: Tweet, apiClient: APIClient = .shared) {
        defer { TweetMutationHub.shared.register(self) }
        self.focalTweet = focalTweet
        self.apiClient = apiClient
        
        // A reply sent from the reply sheet to this post (or to a reply shown here): show it
        NotificationCenter.default.addObserver(forName: NSNotification.Name("Tweetintosh_ReplyPosted"), object: nil, queue: .main) { [weak self] note in
            guard let self = self, let targetId = note.userInfo?["targetId"] as? String else { return }
            if targetId == self.focalTweet.id || self.replies.contains(where: { $0.id == targetId }) || self.ancestors.contains(where: { $0.id == targetId }) {
                self.refreshAfterReply()
            }
        }
        
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
        
        error = nil
        
        // A detail page warmed by hovering opens already filled in; it is only refetched if it has gone stale. This
        // happens before the page's first frame on purpose: filling it in afterwards lays the whole table out twice.
        if let cached = TweetDetailPrefetcher.shared.cached(focalTweet.id) {
            detailLogger.notice("detail opened from prefetch cache \(self.focalTweet.id, privacy: .public)")
            applyDetail(cached.detail)
            if Date().timeIntervalSince(cached.fetchedAt) >= 30 { fetchDetail(hasCached: true) }
            return
        }
        isLoading = true
        fetchDetail(hasCached: false)
    }
    
    private func fetchDetail(hasCached: Bool) {
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
    
    // MARK: - Refresh
    
    // Fetches the page again (pull-down, Command+R, or after a reply was sent). New replies appear; replies already
    // sent from this page stay in place until X starts listing them.
    func refresh(minimumDuration: TimeInterval = 0.8) {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        let started = Date()
        apiClient.fetchTweetDetail(tweetId: focalTweet.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let finish = {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if case .success(let data) = result {
                            self.applyDetail(data)
                            // Keep own replies X hasn't listed yet; drop the ones it now lists
                            let listed = Set(self.replies.map { $0.id })
                            self.ownPendingReplies = self.ownPendingReplies.filter { !listed.contains($0.key) }
                            self.replies.insert(contentsOf: self.ownPendingReplies.values.sorted { $0.id > $1.id }, at: 0)
                        }
                        self.isRefreshing = false
                    }
                }
                let wait = max(0, minimumDuration - Date().timeIntervalSince(started))
                if wait > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: finish) } else { finish() }
            }
        }
    }
    
    // X can take a moment to list a reply that was just sent, so the page is refreshed shortly after and again a
    // little later
    func refreshAfterReply() {
        for delay in [1.2, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh(minimumDuration: 0)
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
                    self.ownPendingReplies[newTweetId] = newTweet
                    self.refreshAfterReply()
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
    // Sent through the timeline, which changes its own copies and then every registered page, this one included: a like
    // made here shows on Home, and one made on Home or another page shows here.
    private func mutateTweet(id: String, transform: (inout Tweet) -> Void) {
        TimelineViewModel.shared.mutateTweet(id: id, transform: transform)
    }

    func copy(of id: String) -> Tweet? {
        if focalTweet.canonicalId == id { return focalTweet }
        return (ancestors + replies).first { $0.canonicalId == id }
    }

    func applyMutation(id: String, transform: (inout Tweet) -> Void) {
        if focalTweet.canonicalId == id {
            transform(&focalTweet)
        }
        for i in ancestors.indices where ancestors[i].canonicalId == id {
            transform(&ancestors[i])
        }
        for i in replies.indices where replies[i].canonicalId == id {
            transform(&replies[i])
        }
    }
    
    // MARK: - Optimistic Like Toggle
    func toggleLike(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let postId = tweet.canonicalId
        let wasLiked = tweet.isFavorited
        let willLike = !wasLiked
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        mutateTweet(id: postId) { t in
            t.isFavorited = willLike
            t.favoriteCount = max(0, t.favoriteCount + (willLike ? 1 : -1))
        }
        
        let settle: (Result<Void, APIError>) -> Void = {
            EngagementGuard.settle($0, kind: .like, turnedOn: willLike, postId: postId)
        }
        if willLike {
            apiClient.favoriteTweet(id: tweetId, completion: settle)
        } else {
            apiClient.unfavoriteTweet(id: tweetId, completion: settle)
        }
    }
    
    // MARK: - Optimistic Retweet Toggle
    func toggleRetweet(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let postId = tweet.canonicalId
        let wasRetweeted = tweet.isRetweeted
        let willRetweet = !wasRetweeted
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        mutateTweet(id: postId) { t in
            t.isRetweeted = willRetweet
            t.retweetCount = max(0, t.retweetCount + (willRetweet ? 1 : -1))
        }
        
        let settle: (Result<Void, APIError>) -> Void = {
            EngagementGuard.settle($0, kind: .repost, turnedOn: willRetweet, postId: postId)
        }
        if willRetweet {
            apiClient.retweet(id: tweetId, completion: settle)
        } else {
            apiClient.unretweet(id: tweetId, completion: settle)
        }
    }
    
    // MARK: - Optimistic Bookmark Toggle
    func toggleBookmark(for tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
        let tweetId = tweet.id
        let postId = tweet.canonicalId
        let wasBookmarked = tweet.isBookmarked
        let willBookmark = !wasBookmarked
        
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        mutateTweet(id: postId) { t in
            t.isBookmarked = willBookmark
            t.bookmarkCount = max(0, t.bookmarkCount + (willBookmark ? 1 : -1))
        }
        TimelineViewModel.shared.bookmarkStateChanged(postId: postId, isBookmarked: willBookmark)
        
        let settle: (Result<Void, APIError>) -> Void = {
            EngagementGuard.settle($0, kind: .bookmark, turnedOn: willBookmark, postId: postId)
        }
        if willBookmark {
            apiClient.bookmark(id: tweetId, completion: settle)
        } else {
            apiClient.unbookmark(id: tweetId, completion: settle)
        }
    }
}
