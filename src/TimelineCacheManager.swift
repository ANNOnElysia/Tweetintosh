//
//  TimelineCacheManager.swift
//  MaX - Headless Data-driven Client
//

import Foundation

final class TimelineCacheManager {
    static let shared = TimelineCacheManager()
    
    private let maxDir: URL
    private let queue = DispatchQueue(label: "com.antigravity.max.cache", qos: .utility)
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MaX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.maxDir = dir
    }
    
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
    
    func saveSnapshot(feed: HomeFeedType = .forYou, listId: String? = nil, tweets: [Tweet], topCursor: String?, bottomCursor: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let snapshot = TimelineSnapshot(
                tweets: Array(tweets.prefix(100)), // Cache up to 100 recent tweets
                topCursor: topCursor,
                bottomCursor: bottomCursor,
                savedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: self.cacheURL(for: feed, listId: listId), options: .atomic)
            }
        }
    }
    
    func clearCache(feed: HomeFeedType? = nil, listId: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let feed = feed {
                try? FileManager.default.removeItem(at: self.cacheURL(for: feed, listId: listId))
            } else {
                for f in HomeFeedType.allCases {
                    try? FileManager.default.removeItem(at: self.cacheURL(for: f))
                }
                try? FileManager.default.removeItem(at: self.maxDir.appendingPathComponent("timeline_cache.json"))
            }
        }
    }
}
