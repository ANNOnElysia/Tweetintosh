//
//  NotificationCacheManager.swift
//  MaX - Headless Data-driven Client
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
    
    private let cacheURL: URL
    private let queue = DispatchQueue(label: "com.antigravity.max.notifcache", qos: .utility)
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maxDir = appSupport.appendingPathComponent("MaX", isDirectory: true)
        try? FileManager.default.createDirectory(at: maxDir, withIntermediateDirectories: true)
        self.cacheURL = maxDir.appendingPathComponent("notifications_cache.json")
    }
    
    func loadCachedSnapshot() -> NotificationSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NotificationSnapshot.self, from: data)
    }
    
    func saveSnapshot(items: [NotificationItem], topCursor: String?, bottomCursor: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let snapshot = NotificationSnapshot(
                items: Array(items.prefix(100)),
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
