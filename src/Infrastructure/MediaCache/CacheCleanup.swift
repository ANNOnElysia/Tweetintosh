//
//  CacheCleanup.swift
//  Tweetintosh
//
//  The automatic media-cache cleanup setting: a switch, and the size the cache may reach.
//

import Foundation
import Observation

// The automatic cleanup setting: a switch, on by default, and a size from 100 MB to 500 MB. The far end of the slider
// follows the disk instead, letting the cache use 1% of the free space, so a roomy Mac keeps more and a full one less.
@Observable
final class CacheCleanup {
    static let shared = CacheCleanup()

    static let sizesMB = Array(stride(from: 100, through: 500, by: 50))
    // The slider's last stop, past 500 MB
    static let followsFreeSpace = sizesMB.count

    private static let onKey = "Tweetintosh_AutoCleanCache"
    private static let stopKey = "Tweetintosh_CacheLimitStop"

    var isOn: Bool {
        didSet {
            UserDefaults.standard.set(isOn, forKey: Self.onKey)
            MediaCacheManager.shared.pruneCache()
        }
    }

    // An index into sizesMB, or followsFreeSpace. Cleared only when the slider is let go (see Settings), so dragging
    // down and back up does not delete anything on the way.
    var stop: Int {
        didSet { UserDefaults.standard.set(stop, forKey: Self.stopKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        isOn = defaults.object(forKey: Self.onKey) as? Bool ?? true
        let saved = defaults.object(forKey: Self.stopKey) as? Int ?? Self.sizesMB.firstIndex(of: 450)!
        stop = min(max(saved, 0), Self.followsFreeSpace)
    }

    static func bytes(atStop stop: Int) -> Int64 {
        // Decimal, as the Finder and ByteCountFormatter count, so the 200 MB stop reads "200 MB"
        let megabyte: Int64 = 1_000_000
        guard stop >= followsFreeSpace else { return Int64(sizesMB[max(stop, 0)]) * megabyte }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return max(free / 100, Int64(sizesMB[0]) * megabyte)
    }

    // Read on the cache's own queue as well, so it goes to UserDefaults rather than the observed properties
    static func currentLimitBytes() -> Int64? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: onKey) as? Bool ?? true else { return nil }
        let stop = defaults.object(forKey: stopKey) as? Int ?? sizesMB.firstIndex(of: 450)!
        return bytes(atStop: stop)
    }
}
