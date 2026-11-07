//
//  Preloading.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Preloading modelled on X's web client: hovering a person warms their profile (X's hover card calls preload()
//  on hover-in and fetches the user "if needed"), and hovering a post warms its detail page (X ships a
//  tweet-details prefetch switch). Results are cached briefly so the page opens already filled in.
//

import Foundation
import SwiftUI
import os

private let preloadLog = Logger(subsystem: "com.anno.tweetintosh", category: "preload")

// MARK: - Hover Dwell

// Runs an action only after the pointer has rested on something, so scrolling or sweeping the mouse across
// a timeline doesn't fire a request per row. One pending action per kind, because the pointer is in one place.
final class HoverPreloader {
    static let shared = HoverPreloader()

    private struct Pending {
        var key: String
        var work: DispatchWorkItem
    }
    private var pending: [String: Pending] = [:]

    func begin(kind: String, key: String, delay: TimeInterval, action: @escaping () -> Void) {
        pending[kind]?.work.cancel()
        let work = DispatchWorkItem { action() }
        pending[kind] = Pending(key: key, work: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func end(kind: String, key: String) {
        guard let current = pending[kind], current.key == key else { return }
        current.work.cancel()
        pending[kind] = nil
    }
}

extension View {
    func preloadOnHover(kind: String, key: String, delay: TimeInterval, _ action: @escaping () -> Void) -> some View {
        onHover { inside in
            if inside {
                HoverPreloader.shared.begin(kind: kind, key: key, delay: delay, action: action)
            } else {
                HoverPreloader.shared.end(kind: kind, key: key)
            }
        }
    }
}

// MARK: - Profiles

final class ProfilePreloader {
    static let shared = ProfilePreloader()

    struct Entry {
        var profile: UserProfile?
        var posts: (items: [ProfileTimelineItem], cursor: String?)?
        var fetchedAt: Date
    }

    private let ttl: TimeInterval = 300
    private let maxEntries = 24
    private let maxInFlight = 3
    private var entries: [String: Entry] = [:]
    private var inFlight = Set<String>()

    private func key(_ screenName: String) -> String { screenName.lowercased() }

    // A fresh preloaded entry, if any
    func cached(_ screenName: String) -> Entry? {
        guard let entry = entries[key(screenName)], Date().timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        return entry
    }

    // Warms the profile header and the first page of posts ("if needed": skipped when fresh or already loading)
    func preload(_ user: TweetUser) {
        let name = key(user.screenName)
        guard !name.isEmpty, cached(name) == nil, !inFlight.contains(name), inFlight.count < maxInFlight else { return }
        inFlight.insert(name)
        preloadLog.notice("preload profile @\(user.screenName, privacy: .public)")
        
        APIClient.shared.fetchUserProfile(screenName: user.screenName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard case .success(let profile) = result else {
                    self.inFlight.remove(name)
                    return
                }
                var entry = Entry(profile: profile, posts: nil, fetchedAt: Date())
                self.store(entry, for: name)

                APIClient.shared.fetchUserTimeline(.posts, userId: profile.user.id, cursor: nil) { [weak self] postsResult in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if case .success(let page) = postsResult {
                            entry.posts = (page.items, page.bottomCursor)
                            self.store(entry, for: name)
                        }
                        self.inFlight.remove(name)
                    }
                }
            }
        }
    }

    // What a profile preview shows, without the posts: a click that starts a deep press usually goes no further, so
    // this has to stay cheap. Fetched only for people who came without a bio or banner, as the preview itself would.
    func preloadCard(_ user: TweetUser) {
        let name = key(user.screenName)
        guard !name.isEmpty else { return }
        if user.bio != nil || user.bannerUrl != nil {
            warmCardImages(user)
            return
        }
        if let profile = cached(name)?.profile {
            warmCardImages(profile.user)
            return
        }
        guard !inFlight.contains(name), inFlight.count < maxInFlight else { return }
        inFlight.insert(name)
        preloadLog.notice("preload card @\(user.screenName, privacy: .public)")
        APIClient.shared.fetchUserProfile(screenName: user.screenName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inFlight.remove(name)
                if case .success(let profile) = result {
                    self.store(Entry(profile: profile, posts: nil, fetchedAt: Date()), for: name)
                    self.warmCardImages(profile.user)
                }
            }
        }
    }

    // The same addresses the preview asks for, so they are waiting in the cache when it opens
    private func warmCardImages(_ user: TweetUser) {
        let urls = [
            user.bannerUrl.map { $0 + "/600x200" },
            user.avatarUrl?.replacingOccurrences(of: "_bigger", with: "_400x400")
        ].compactMap { $0 }
        MediaCacheManager.shared.prefetchImages(urls: urls)
    }

    private func store(_ entry: Entry, for name: String) {
        entries[name] = entry
        if entries.count > maxEntries {
            let oldest = entries.min { $0.value.fetchedAt < $1.value.fetchedAt }?.key
            if let oldest = oldest, oldest != name { entries.removeValue(forKey: oldest) }
        }
    }
}

// MARK: - Tweet Detail

final class TweetDetailPrefetcher: TweetMutationTarget {
    static let shared = TweetDetailPrefetcher()

    private init() {
        TweetMutationHub.shared.register(self)
    }

    // A page warmed before a like, repost or bookmark opens showing it: the cached copy is changed along with the rest
    func applyMutation(id: String, transform: (inout Tweet) -> Void) {
        for (key, var entry) in entries {
            var changed = false
            if var focal = entry.detail.focalTweet, focal.canonicalId == id {
                transform(&focal)
                entry.detail.focalTweet = focal
                changed = true
            }
            for i in entry.detail.ancestors.indices where entry.detail.ancestors[i].canonicalId == id {
                transform(&entry.detail.ancestors[i])
                changed = true
            }
            for i in entry.detail.replies.indices where entry.detail.replies[i].canonicalId == id {
                transform(&entry.detail.replies[i])
                changed = true
            }
            if changed { entries[key] = entry }
        }
    }

    typealias Detail = (focalTweet: Tweet?, ancestors: [Tweet], replies: [Tweet], bottomCursor: String?)
    struct Entry {
        var detail: Detail
        var fetchedAt: Date
    }

    private let ttl: TimeInterval = 120
    private let maxEntries = 30
    private let maxInFlight = 3
    private var entries: [String: Entry] = [:]
    private var inFlight = Set<String>()

    func cached(_ tweetId: String) -> Entry? {
        guard let entry = entries[tweetId], Date().timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        return entry
    }

    func prefetch(_ tweet: Tweet) {
        let id = tweet.id
        guard !id.isEmpty, !tweet.isPromoted, cached(id) == nil, !inFlight.contains(id), inFlight.count < maxInFlight else { return }
        inFlight.insert(id)
        preloadLog.notice("prefetch detail \(id, privacy: .public)")
        
        APIClient.shared.fetchTweetDetail(tweetId: id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inFlight.remove(id)
                guard case .success(let detail) = result else { return }
                self.entries[id] = Entry(detail: detail, fetchedAt: Date())
                if self.entries.count > self.maxEntries,
                   let oldest = self.entries.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key, oldest != id {
                    self.entries.removeValue(forKey: oldest)
                }
            }
        }
    }
}
