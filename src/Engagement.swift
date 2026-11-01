//
//  Engagement.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Engagement rules shared by every screen: what to do when the author has blocked you, how rejections from X
//  are reported, and keeping every on-screen copy of a post in sync when you like, repost, or bookmark it.
//

import Foundation

// MARK: - Blocked Authors

// Accounts known to have blocked the signed-in user. Not every payload carries the flag (profile timelines
// don't), so any place that sees `blocked_by` records it here and every post by that author honours it.
final class BlockedByRegistry {
    static let shared = BlockedByRegistry()
    
    private let lock = NSLock()
    private var ids = Set<String>()
    
    func insert(_ id: String) {
        guard !id.isEmpty else { return }
        lock.lock(); ids.insert(id); lock.unlock()
    }
    
    func contains(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ids.contains(id)
    }
}

extension TweetUser {
    // This user has blocked you: you can read their posts but not like, repost, bookmark, reply, or follow
    var hasBlockedYou: Bool { blockedBy == true || BlockedByRegistry.shared.contains(id) }
}

enum EngagementGuard {
    // When an author has blocked you, X still lets you read their posts but refuses likes, reposts,
    // bookmarks, replies, and follows. Returns false (after telling the user why) if the action can't go ahead.
    static func allows(_ tweet: Tweet) -> Bool {
        guard tweet.author.hasBlockedYou else { return true }
        AppToastManager.shared.show(
            LocalizationManager.shared.format("engagement_blocked", ["name": tweet.author.formattedHandle]),
            icon: "hand.raised.fill",
            duration: 3.6
        )
        return false
    }

    // Tells the user why X refused an action (e.g. "You have been blocked from ...")
    static func reportFailure(_ error: APIError) {
        var reason = error.localizedDescription
        guard !reason.isEmpty else { return }
        // X's block refusals are English and cite user ids ("... is blocked by tweet owner (uid: ...)"):
        // show a plain localized explanation instead
        if reason.localizedCaseInsensitiveContains("blocked") {
            reason = LocalizationManager.shared.t("engagement_blocked_generic")
        }
        // A limit reads as something to wait out, not as a rejection
        var icon = "hand.raised.fill"
        if case .refused(let code, _) = error { icon = XFailure.iconName(for: code) }
        DispatchQueue.main.async {
            AppToastManager.shared.show(reason, icon: icon, duration: icon == "hourglass" ? 6 : 3.6)
        }
    }
}

extension APIClient {
    // X's explanation from an error response body: {"errors":[{"code":162,"message":"..."}]}
    static func errorMessage(from data: Data?) -> String? {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [[String: Any]] else { return nil }
        let message = errors.compactMap { $0["message"] as? String }.joined(separator: ", ")
        return message.isEmpty ? nil : message
    }
}

// MARK: - Cross-Screen Post Updates

// A post can be on screen in several places at once (timeline, tweet detail, a profile tab, search results).
// Liking it in one must update the others, so those pages register here and receive every post mutation.
protocol TweetMutationTarget: AnyObject {
    func applyMutation(id: String, transform: (inout Tweet) -> Void)
}

final class TweetMutationHub {
    static let shared = TweetMutationHub()
    
    private let targets = NSHashTable<AnyObject>.weakObjects()
    
    func register(_ target: TweetMutationTarget) {
        targets.add(target)
    }
    
    func apply(id: String, transform: (inout Tweet) -> Void) {
        for case let target as TweetMutationTarget in targets.allObjects {
            target.applyMutation(id: id, transform: transform)
        }
    }
}
