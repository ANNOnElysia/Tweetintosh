//
//  MediaCacheManager.swift
//  MaX - Headless Data-driven Client
//

import AppKit
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
    private let ioQueue = DispatchQueue(label: "com.antigravity.max.mediacache.io", qos: .utility)
    private let downloadQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.antigravity.max.mediacache.download"
        q.maxConcurrentOperationCount = 6
        q.qualityOfService = .utility
        return q
    }()
    
    // Size and pruning limits
    private let maxDiskBytes: Int64 = 450 * 1024 * 1024 // 450 MB total limit
    private let maxAgeSeconds: TimeInterval = 7 * 86400  // 7 days TTL
    
    @Published var formattedCacheSize: String = "0 B"
    
    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let maxCaches = cachesDir.appendingPathComponent("com.antigravity.max", isDirectory: true)
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
    
    // MARK: - Prefetching Engine (Background Concurrency Controlled)
    func prefetchImages(urls: [String]) {
        for urlStr in urls {
            // Existence check only: decoding cached files here would block the caller (often the main thread)
            if hasCachedImage(for: urlStr) { continue }
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
        if cachedVideoURL(for: urlStr) != nil { return }
        guard let url = URL(string: urlStr) else { return }
        let path = videoFilePath(for: urlStr)
        
        let op = BlockOperation {
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
    
    // MARK: - Cache Eviction & Cleanup Strategy ("找机会清理掉")
    // 1. Time-to-Live: Deletes files older than 7 days
    // 2. LRU: If total size exceeds maxDiskBytes, evicts oldest modified files down to 70% threshold
    func pruneCache() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let fm = FileManager.default
            
            for folder in [self.imagesDir, self.videosDir] {
                guard let fileURLs = try? fm.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: .skipsHiddenFiles
                ) else {
                    continue
                }
                
                var totalSize: Int64 = 0
                var fileRecords: [(url: URL, date: Date, size: Int64)] = []
                
                for fileURL in fileURLs {
                    let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    let date = values?.contentModificationDate ?? now
                    let size = Int64(values?.fileSize ?? 0)
                    
                    // 1. TTL Pruning
                    if now.timeIntervalSince(date) > self.maxAgeSeconds {
                        try? fm.removeItem(at: fileURL)
                        continue
                    }
                    
                    totalSize += size
                    fileRecords.append((fileURL, date, size))
                }
                
                // 2. LRU Pruning
                let folderLimit: Int64 = (folder == self.imagesDir) ? 350 * 1024 * 1024 : 100 * 1024 * 1024
                if totalSize > folderLimit {
                    let targetSize = Int64(Double(folderLimit) * 0.70)
                    let sorted = fileRecords.sorted { $0.date < $1.date }
                    var currentTotal = totalSize
                    for item in sorted {
                        if currentTotal <= targetSize { break }
                        try? fm.removeItem(at: item.url)
                        currentTotal -= item.size
                    }
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
