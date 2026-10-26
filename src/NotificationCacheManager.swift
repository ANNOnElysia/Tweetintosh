//
//  NotificationCacheManager.swift
//  Tweetintosh - Headless Data-driven Client
//

import Foundation

struct NotificationSnapshot: Codable {
    var items: [NotificationItem]
    var topCursor: String?
    var bottomCursor: String?
    var savedAt: Date
}

final class NotificationCacheManager {
    static let shared = NotificationCacheManager()
    
    // The active account's data folder, so each account keeps its own cached notifications
    private var cacheURL: URL { AccountManager.shared.activeDirectory.appendingPathComponent("notifications_cache.json") }
    private let queue = DispatchQueue(label: "com.anno.tweetintosh.notifcache", qos: .utility)
    
    private init() {}
    
    func loadCachedSnapshot() -> NotificationSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NotificationSnapshot.self, from: data)
    }
    
    func saveSnapshot(items: [NotificationItem], topCursor: String?, bottomCursor: String?) {
        // The file is chosen now, not when the write runs, so a write queued just before an account switch
        // can't land in the next account's folder
        let url = cacheURL
        queue.async {
            let snapshot = NotificationSnapshot(
                items: Array(items.prefix(100)),
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
    
    func clearCache() {
        let url = cacheURL
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
