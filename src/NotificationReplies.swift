//
//  NotificationReplies.swift
//  Tweetintosh - Headless Data-driven Client
//
//  X's notifications feed that this app reads reports likes, reposts and follows, but not replies or mentions: X's own
//  apps get those from a newer feed. They are found here by searching for posts that reply to or mention the signed-in
//  account, and merged into the notification list by time.
//

import Foundation

extension APIClient {
    typealias NotificationPage = (items: [NotificationItem], topCursor: String?, bottomCursor: String?)

    // The notifications, with replies and mentions of the account merged in
    func fetchNotificationsWithReplies(completion: @escaping (Result<NotificationPage, APIError>) -> Void) {
        fetchNotifications { [weak self] result in
            guard let self = self else { return }
            guard case .success(let page) = result,
                  let me = AccountManager.shared.active, !me.screenName.isEmpty else {
                completion(result)
                return
            }
            self.fetchSearch(query: "@\(me.screenName) -from:\(me.screenName)", tab: .latest, cursor: nil) { searchResult in
                guard case .success(let found) = searchResult else {
                    completion(.success(page))   // the other notifications are still shown
                    return
                }
                // Only as far back as the notifications reach, so the list has no gap in the middle
                let oldest = page.items.map(\.createdAt).min()
                let extra: [NotificationItem] = found.tweets.compactMap { tweet in
                    guard tweet.author.id != me.id, !tweet.isPromoted, !tweet.isRetweet else { return nil }
                    if let oldest = oldest, tweet.createdAt < oldest { return nil }
                    let isReply = tweet.inReplyToStatusId != nil
                    return NotificationItem(
                        id: "post-\(tweet.id)",
                        type: isReply ? .reply : .mention,
                        actors: [tweet.author],
                        actionSummary: "",
                        targetTweetSnippet: nil,
                        targetTweetId: tweet.id,
                        replyBody: tweet.displayBodyText.isEmpty ? tweet.text : tweet.displayBodyText,
                        createdAt: tweet.createdAt
                    )
                }
                let known = Set(page.items.map(\.id))
                let merged = (page.items + extra.filter { !known.contains($0.id) }).sorted { $0.createdAt > $1.createdAt }
                completion(.success((merged, page.topCursor, page.bottomCursor)))
            }
        }
    }
}
