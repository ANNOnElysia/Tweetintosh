//
//  DebugSupport.swift
//  Tweetintosh - Headless Data-driven Client
//  Scaffolding for looking at the post page and its replies while that work is in progress. It stays inert unless
//  MAX_DEBUG_DETAIL is set in the environment, so a normal launch never pays for it, and release builds keep working
//  the same way (the checks are at runtime, not #if DEBUG, because the app is built and run in release).
//
//  Usage: MAX_DEBUG_DETAIL=1 open -a Tweetintosh
//  Remove this file and its two call sites once the reply threading settles.

import Foundation
import os

enum DebugSupport {
    /// Set `MAX_DEBUG_DETAIL` in the environment to turn the reply scaffolding on.
    static let isDetailLoggingEnabled = ProcessInfo.processInfo.environment["MAX_DEBUG_DETAIL"] != nil

    private static let logger = Logger(subsystem: "com.anno.tweetintosh", category: "replydebug")

    // MARK: - Opening a post with a long reply list

    /// Opens a post that has plenty of replies a few seconds after launch, so the reply page can be inspected
    /// without clicking through the timeline by hand. Opening it by hand still works with the timeline.
    static func openBusyReplyPostAfterLaunch() {
        guard isDetailLoggingEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
            guard let tweet = TimelineViewModel.shared.tweets.first(where: { $0.replyCount > 25 }) else {
                logger.notice("no post with more than 25 replies is in the timeline yet")
                return
            }
            NavigationManager.shared.openTweetDetail(tweet)
        }
    }

    // MARK: - Dumping how the replies arrived

    /// Writes the focal post, each reply with the post it answers, and the threads they were grouped into. The
    /// threads are only built when the scaffolding is on, which is why they arrive as an autoclosure.
    static func repliesDidChange(focal: Tweet, replies: [Tweet], threads: @autoclosure () -> [[Tweet]]) {
        guard isDetailLoggingEnabled else { return }
        let authorId = focal.author.id
        logger.notice("focal=\(focal.id, privacy: .public) author=\(authorId, privacy: .public) replies=\(replies.count, privacy: .public)")
        for (index, reply) in replies.enumerated() {
            let isAuthor = reply.author.id == authorId ? "(AUTHOR)" : ""
            let parent = reply.inReplyToStatusId ?? "-"
            logger.notice("#\(index, privacy: .public) id=\(reply.id, privacy: .public) parent=\(parent, privacy: .public) by=\(reply.author.screenName, privacy: .public)\(isAuthor, privacy: .public) replyCount=\(reply.replyCount, privacy: .public)")
        }
        for (index, thread) in threads().enumerated() {
            let ids = thread.map { $0.id.suffix(5) }.joined(separator: ",")
            logger.notice("thread \(index, privacy: .public): \(ids, privacy: .public)")
        }
    }
}
