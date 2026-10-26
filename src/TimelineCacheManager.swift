//
//  TimelineCacheManager.swift
//  Tweetintosh - Headless Data-driven Client
//

import Foundation

final class TimelineCacheManager {
    static let shared = TimelineCacheManager()
    
    // The active account's data folder, so each account keeps its own cached timelines and lists
    private var maxDir: URL { AccountManager.shared.activeDirectory }
    private let queue = DispatchQueue(label: "com.anno.tweetintosh.cache", qos: .utility)
    
    private init() {}
    
    private func cacheURL(for feed: HomeFeedType, listId: String? = nil) -> URL {
        if feed == .list, let listId = listId, !listId.isEmpty {
            return maxDir.appendingPathComponent("timeline_cache_list_\(listId).json")
        }
        return maxDir.appendingPathComponent("timeline_cache_\(feed.rawValue).json")
    }
    
    func loadCachedSnapshot(feed: HomeFeedType = .forYou, listId: String? = nil) -> TimelineSnapshot? {
        let url = cacheURL(for: feed, listId: listId)
        // If specific feed cache doesn't exist yet, check legacy timeline_cache.json for forYou
        let fileToRead = FileManager.default.fileExists(atPath: url.path) ? url : (feed == .forYou ? maxDir.appendingPathComponent("timeline_cache.json") : url)
        guard let data = try? Data(contentsOf: fileToRead) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TimelineSnapshot.self, from: data)
    }
    
    // MARK: - User Lists Cache
    private var userListsCacheURL: URL {
        return maxDir.appendingPathComponent("user_twitter_lists.json")
    }
    
    func loadCachedUserLists() -> [TwitterList] {
        guard let data = try? Data(contentsOf: userListsCacheURL) else { return [] }
        return (try? JSONDecoder().decode([TwitterList].self, from: data)) ?? []
    }
    
    func saveCachedUserLists(_ lists: [TwitterList]) {
        let url = userListsCacheURL   // chosen now, so a write queued before an account switch stays with its account
        queue.async {
            if let data = try? JSONEncoder().encode(lists) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    func saveSnapshot(feed: HomeFeedType = .forYou, listId: String? = nil, tweets: [Tweet], topCursor: String?, bottomCursor: String?) {
        let url = cacheURL(for: feed, listId: listId)
        queue.async {
            let snapshot = TimelineSnapshot(
                tweets: Array(tweets.prefix(100)), // Cache up to 100 recent tweets
                topCursor: topCursor,
                bottomCursor: bottomCursor,
                savedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    func clearCache(feed: HomeFeedType? = nil, listId: String? = nil) {
        let dir = maxDir
        let urls: [URL]
        if let feed = feed {
            urls = [cacheURL(for: feed, listId: listId)]
        } else {
            urls = HomeFeedType.allCases.map { cacheURL(for: $0) } + [dir.appendingPathComponent("timeline_cache.json")]
        }
        queue.async {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
    }
}
