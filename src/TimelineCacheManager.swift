//
//  TimelineCacheManager.swift
//  MaX - Headless Data-driven Client
//

import Foundation

final class TimelineCacheManager {
    static let shared = TimelineCacheManager()
    
    private let cacheURL: URL
    private let queue = DispatchQueue(label: "com.antigravity.max.cache", qos: .utility)
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maxDir = appSupport.appendingPathComponent("MaX", isDirectory: true)
        try? FileManager.default.createDirectory(at: maxDir, withIntermediateDirectories: true)
        self.cacheURL = maxDir.appendingPathComponent("timeline_cache.json")
    }
    
    func loadCachedSnapshot() -> TimelineSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TimelineSnapshot.self, from: data)
    }
    
    func saveSnapshot(tweets: [Tweet], topCursor: String?, bottomCursor: String?) {
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
                try? data.write(to: self.cacheURL, options: .atomic)
            }
        }
    }
    
    func clearCache() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.cacheURL)
        }
    }
}
