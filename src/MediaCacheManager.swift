//
//  MediaCacheManager.swift
//  Tweetintosh - Headless Data-driven Client
//

import AppKit
import Observation
import Foundation
import CryptoKit
import ImageIO

final class MediaCacheManager: ObservableObject {
    static let shared = MediaCacheManager()
    
    // Level 1: In-memory decoded image cache (fast access, OS purges on memory pressure)
    private let memoryCache = NSCache<NSString, NSImage>()
    
    // Level 2: Persistent on-disk media cache
    private let baseDir: URL
    private let imagesDir: URL
    private let videosDir: URL
    
    // Concurrency queues
    private let ioQueue = DispatchQueue(label: "com.anno.tweetintosh.mediacache.io", qos: .utility)
    private let downloadQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.anno.tweetintosh.mediacache.download"
        q.maxConcurrentOperationCount = 6
        q.qualityOfService = .utility
        return q
    }()
    
    @Published var formattedCacheSize: String = "0 B"
    
    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let maxCaches = cachesDir.appendingPathComponent("com.anno.tweetintosh", isDirectory: true)
        let base = maxCaches.appendingPathComponent("MediaCache", isDirectory: true)
        self.baseDir = base
        self.imagesDir = base.appendingPathComponent("images", isDirectory: true)
        self.videosDir = base.appendingPathComponent("videos", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        
        memoryCache.countLimit = 400
        memoryCache.totalCostLimit = 160 * 1024 * 1024 // 160 MB memory limit
        
        // Initial size calculation
        updateFormattedSize()
        
        // Automatic lifecycle cleanup opportunities ("找机会清理掉")
        // 1. Prune stale cache 5 seconds after launch (avoids startup contention)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.pruneCache()
        }
        
        // 2. Prune when app resigns active / goes to background
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.pruneCache()
        }
    }
    
    // MARK: - Key & File Path Utilities
    private func fileKey(for urlStr: String) -> String {
        SHA256.hash(data: Data(urlStr.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    
    private func imageFilePath(for urlStr: String) -> URL {
        let key = fileKey(for: urlStr)
        return imagesDir.appendingPathComponent("\(key).img")
    }
    
    private func videoFilePath(for urlStr: String) -> URL {
        let key = fileKey(for: urlStr)
        let ext = (urlStr as NSString).pathExtension.components(separatedBy: "?").first ?? "mp4"
        return videosDir.appendingPathComponent("\(key).\(ext)")
    }
    
    func formatThumbUrl(_ original: String) -> String {
        if original.contains("pbs.twimg.com/media") {
            if original.contains("?") {
                return original
            }
            return "\(original)?format=jpg&name=medium"
        }
        return original
    }
    
    // MARK: - Image Retrieval (Memory only vs Disk)
    // targetPixelSize: when set, the image is downsampled to aspect-fill that box and cached under its own key,
    // so full-resolution lookups (lightbox, save, copy) never receive a thumbnail.
    func memoryImage(for urlStr: String, targetPixelSize: CGSize? = nil) -> NSImage? {
        memoryCache.object(forKey: memoryKey(for: urlStr, targetPixelSize: targetPixelSize))
    }

    // Reads and decodes synchronously; call off the main thread.
    func diskImage(for urlStr: String, targetPixelSize: CGSize? = nil) -> NSImage? {
        let path = imageFilePath(for: urlStr)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let img = cacheDecodedImage(from: data, for: urlStr, targetPixelSize: targetPixelSize) else {
            return nil
        }
        // Touch file date for LRU tracking
        ioQueue.async {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        }
        return img
    }

    // Cheap existence check (no disk read or decode), safe on the main thread.
    func hasCachedImage(for urlStr: String) -> Bool {
        memoryImage(for: urlStr) != nil || FileManager.default.fileExists(atPath: imageFilePath(for: urlStr).path)
    }

    // Decodes freshly downloaded bytes (call off the main thread), caches the bitmap in memory and persists the raw bytes.
    func storeImageData(_ data: Data, for urlStr: String, targetPixelSize: CGSize? = nil) -> NSImage? {
        guard let img = cacheDecodedImage(from: data, for: urlStr, targetPixelSize: targetPixelSize) else { return nil }
        writeImageDataIfNeeded(data, for: urlStr)
        return img
    }

    private func memoryKey(for urlStr: String, targetPixelSize: CGSize?) -> NSString {
        guard let size = targetPixelSize else { return urlStr as NSString }
        return "\(urlStr)#\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private func cacheDecodedImage(from data: Data, for urlStr: String, targetPixelSize: CGSize?) -> NSImage? {
        guard let cg = Self.decodeImage(data: data, targetPixelSize: targetPixelSize) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memoryCache.setObject(img, forKey: memoryKey(for: urlStr, targetPixelSize: targetPixelSize), cost: cg.bytesPerRow * cg.height)
        return img
    }

    // Fully decodes into a bitmap up front (kCGImageSourceShouldCacheImmediately) so drawing never decompresses
    // on the main thread. With a target size, uses ImageIO thumbnailing to decode only the pixels needed for aspect-fill.
    static func decodeImage(data: Data, targetPixelSize: CGSize?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        if let target = targetPixelSize,
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           w > 0, h > 0 {
            let scale = max(target.width / w, target.height / h)
            if scale < 1.0 {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: ceil(max(w, h) * scale)
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func writeImageDataIfNeeded(_ data: Data, for urlStr: String) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let path = self.imageFilePath(for: urlStr)
            if !FileManager.default.fileExists(atPath: path.path) {
                try? data.write(to: path, options: .atomic)
            }
        }
    }
    
    func image(for urlStr: String) -> NSImage? {
        if let mem = memoryImage(for: urlStr) {
            return mem
        }
        return diskImage(for: urlStr)
    }
    
    // MARK: - Image Storage (Memory + Background Disk Save)
    func storeImage(_ img: NSImage, rawData: Data?, for urlStr: String) {
        let nsKey = urlStr as NSString
        // Pre-decode
        if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            _ = cg.width
        }
        memoryCache.setObject(img, forKey: nsKey)
        
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let path = self.imageFilePath(for: urlStr)
            if !FileManager.default.fileExists(atPath: path.path) {
                if let data = rawData {
                    try? data.write(to: path, options: .atomic)
                } else if let tiff = img.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let jpeg = rep.representation(using: .jpeg, properties: [:]) {
                    try? jpeg.write(to: path, options: .atomic)
                }
            }
        }
    }
    
    // MARK: - Video Cache Retrieval
    func cachedVideoURL(for urlStr: String) -> URL? {
        let path = videoFilePath(for: urlStr)
        if FileManager.default.fileExists(atPath: path.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
               let size = attrs[.size] as? Int64, size > 1024 {
                // Touch file date for LRU
                ioQueue.async {
                    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
                }
                return path
            }
        }
        return nil
    }
    
    // MARK: - Video Cache Writing
    // For callers that schedule their own downloads (the Videos tab fetches one video at a time, in order). Call from
    // the download's completion handler: the temporary file is deleted as soon as that handler returns.
    @discardableResult
    func storeDownloadedVideo(at tempURL: URL, for urlStr: String) -> Bool {
        let path = videoFilePath(for: urlStr)
        try? FileManager.default.removeItem(at: path)
        return (try? FileManager.default.moveItem(at: tempURL, to: path)) != nil
    }

    func removeCachedVideo(for urlStr: String) {
        let path = videoFilePath(for: urlStr)
        ioQueue.async {
            try? FileManager.default.removeItem(at: path)
        }
    }

    // MARK: - Prefetching Engine (Background Concurrency Controlled)
    func prefetchImages(urls: [String]) {
        var seen = Set<String>()
        for urlStr in urls where seen.insert(urlStr).inserted {
            guard let url = URL(string: urlStr) else { continue }

            let op = BlockOperation { [weak self] in
                guard let self = self else { return }
                if self.hasCachedImage(for: urlStr) { return }

                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
                let semaphore = DispatchSemaphore(value: 0)

                // Persist raw bytes only; rows decode at their own display size when they appear
                URLSession.shared.dataTask(with: request) { data, _, _ in
                    defer { semaphore.signal() }
                    if let data = data, CGImageSourceCreateWithData(data as CFData, nil) != nil {
                        self.writeImageDataIfNeeded(data, for: urlStr)
                    }
                }.resume()
                
                _ = semaphore.wait(timeout: .now() + 25)
            }
            downloadQueue.addOperation(op)
        }
    }
    
    func prefetchVideo(urlStr: String) {
        guard !urlStr.isEmpty else { return }
        guard let url = URL(string: urlStr) else { return }

        let op = BlockOperation { [weak self] in
            guard let self = self, self.cachedVideoURL(for: urlStr) == nil else { return }
            let path = self.videoFilePath(for: urlStr)
            if FileManager.default.fileExists(atPath: path.path) { return }
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 45)
            let semaphore = DispatchSemaphore(value: 0)
            
            let task = URLSession.shared.downloadTask(with: request) { tempURL, _, error in
                defer { semaphore.signal() }
                guard let temp = tempURL, error == nil else { return }
                try? FileManager.default.moveItem(at: temp, to: path)
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 50)
        }
        downloadQueue.addOperation(op)
    }
    
    func prefetchTweetsMedia(_ tweets: [Tweet], maxTweets: Int = 60) {
        var imageUrls: [String] = []
        var videoUrls: [String] = []
        
        for tweet in tweets.prefix(maxTweets) {
            if let avatar = tweet.author.avatarUrl {
                imageUrls.append(avatar)
            }
            for media in tweet.media {
                let thumb = formatThumbUrl(media.mediaUrl)
                imageUrls.append(thumb)
                
                if media.isVideo, let vInfo = media.videoInfo {
                    if let preview = media.previewUrl {
                        imageUrls.append(preview)
                    }
                    if let bestMp4 = vInfo.highestBitrateVariant?.url ?? vInfo.sortedMp4Variants.first?.url {
                        videoUrls.append(bestMp4)
                    }
                }
            }
            if let q = tweet.quoted {
                if let qAvatar = q.author.avatarUrl {
                    imageUrls.append(qAvatar)
                }
                for qMedia in q.media {
                    imageUrls.append(formatThumbUrl(qMedia.mediaUrl))
                }
            }
        }
        
        prefetchImages(urls: imageUrls)
        for vUrl in videoUrls.prefix(8) { // Prefetch top 8 videos to balance disk I/O & bandwidth
            prefetchVideo(urlStr: vUrl)
        }
    }
    
    // MARK: - Automatic Cleanup
    // Once images and videos together pass the size chosen in Settings, the least recently written go first, down to
    // 80% of it so the next few pages do not set it off again. With the setting off, nothing is cleared on its own.
    func pruneCache() {
        guard let limit = CacheCleanup.currentLimitBytes() else {
            updateFormattedSize()
            return
        }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            var records: [(url: URL, date: Date, size: Int64)] = []
            for folder in [self.imagesDir, self.videosDir] {
                let files = (try? fm.contentsOfDirectory(at: folder,
                                                         includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                         options: .skipsHiddenFiles)) ?? []
                for url in files {
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    records.append((url, values?.contentModificationDate ?? .distantPast, Int64(values?.fileSize ?? 0)))
                }
            }
            var total = records.reduce(Int64(0)) { $0 + $1.size }
            if total > limit {
                let target = limit / 5 * 4
                for item in records.sorted(by: { $0.date < $1.date }) where total > target {
                    try? fm.removeItem(at: item.url)
                    total -= item.size
                }
            }
            self.updateFormattedSize()
        }
    }
    
    func clearAllCache() {
        memoryCache.removeAllObjects()
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            try? fm.removeItem(at: self.imagesDir)
            try? fm.removeItem(at: self.videosDir)
            try? fm.createDirectory(at: self.imagesDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: self.videosDir, withIntermediateDirectories: true)
            self.updateFormattedSize()
        }
    }
    
    func calculateTotalDiskSize() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for folder in [imagesDir, videosDir] {
            if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]) {
                        total += Int64(values.fileSize ?? 0)
                    }
                }
            }
        }
        return total
    }
    
    private func updateFormattedSize() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let bytes = self.calculateTotalDiskSize()
            let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            DispatchQueue.main.async {
                self.formattedCacheSize = formatted
            }
        }
    }
}

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
