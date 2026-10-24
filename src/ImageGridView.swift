//
//  ImageGridView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit

// MARK: - Dynamic Layout State (Window Width & Available Column Tracking)
final class TimelineLayoutState: ObservableObject {
    static let shared = TimelineLayoutState()
    
    @Published var windowWidth: CGFloat = 580
    @Published var windowHeight: CGFloat = 840
    
    // Available width for the tweet right column (minus margins, avatar & spacing)
    var availableColumnWidth: CGFloat {
        max(260, windowWidth - 82)
    }
    
    func updateSize(_ size: CGSize) {
        if abs(windowWidth - size.width) > 1 || abs(windowHeight - size.height) > 1 {
            windowWidth = size.width
            windowHeight = size.height
        }
    }
    
    func updateWidth(_ w: CGFloat) {
        if abs(windowWidth - w) > 1 {
            windowWidth = w
        }
    }
    
    func updateHeight(_ h: CGFloat) {
        if abs(windowHeight - h) > 1 {
            windowHeight = h
        }
    }
}

// MARK: - Image Memory & Disk Cache
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private let prefetchQueue = DispatchQueue(label: "com.antigravity.max.prefetch", qos: .utility)
    
    private init() {
        cache.countLimit = 350
        cache.totalCostLimit = 1024 * 1024 * 140 // 140 MB memory limit
    }
    
    func image(for url: String) -> NSImage? {
        return cache.object(forKey: url as NSString)
    }
    
    func setImage(_ image: NSImage, for url: String) {
        cache.setObject(image, forKey: url as NSString)
    }
    
    func prefetch(urls: [String]) {
        prefetchQueue.async { [weak self] in
            guard let self = self else { return }
            for urlStr in urls {
                if self.image(for: urlStr) != nil { continue }
                guard let url = URL(string: urlStr) else { continue }
                
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
                URLSession.shared.dataTask(with: request) { data, _, _ in
                    if let data = data, let img = NSImage(data: data) {
                        self.setImage(img, for: urlStr)
                    }
                }.resume()
            }
        }
    }
}

// MARK: - Image Loader (Sync Cache Hit)
final class ImageLoader: ObservableObject {
    @Published var loadedImage: NSImage?
    @Published var isLoading = false
    private var currentUrl: String?
    
    init(urlString: String?) {
        self.currentUrl = urlString
        if let urlStr = urlString, let cached = ImageCache.shared.image(for: urlStr) {
            self.loadedImage = cached
        }
    }
    
    func load(urlString: String?) {
        guard let urlStr = urlString else { return }
        self.currentUrl = urlStr
        
        if let cached = ImageCache.shared.image(for: urlStr) {
            if self.loadedImage == nil {
                self.loadedImage = cached
            }
            return
        }
        
        guard !isLoading else { return }
        isLoading = true
        
        guard let url = URL(string: urlStr) else {
            isLoading = false
            return
        }
        
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self else { return }
            if let data = data, let img = NSImage(data: data) {
                ImageCache.shared.setImage(img, for: urlStr)
                DispatchQueue.main.async {
                    if self.currentUrl == urlStr {
                        self.loadedImage = img
                    }
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }.resume()
    }
}

// MARK: - Cached Async Image View
struct CachedAsyncImage: View {
    let urlString: String?
    var placeholderColor: Color = Color(white: 0.08)
    var contentMode: ContentMode = .fill
    
    @StateObject private var loader: ImageLoader
    
    init(urlString: String?, placeholderColor: Color = Color(white: 0.08), contentMode: ContentMode = .fill) {
        self.urlString = urlString
        self.placeholderColor = placeholderColor
        self.contentMode = contentMode
        _loader = StateObject(wrappedValue: ImageLoader(urlString: urlString))
    }
    
    var body: some View {
        ZStack {
            if let image = loader.loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(placeholderColor)
                    .overlay(
                        Group {
                            if loader.isLoading {
                                GrowingArcIndicator(color: Color(white: 0.28), lineWidth: 1.5, size: 16)
                            }
                        }
                    )
            }
        }
        .onAppear {
            loader.load(urlString: urlString)
        }
    }
}

// MARK: - Photo Presentation Views (Proportional Scaling via Apple Hardware Resolution)
struct ImageGridView: View {
    let mediaList: [TweetMedia]
    var tweet: Tweet? = nil
    @ObservedObject var layout = TimelineLayoutState.shared
    @ObservedObject var theme = ThemeManager.shared
    
    private func thumbUrl(_ original: String) -> String {
        if original.contains("pbs.twimg.com/media") {
            if original.contains("?") {
                return original
            }
            return "\(original)?format=jpg&name=medium"
        }
        return original
    }
    
    var body: some View {
        Group {
            if mediaList.isEmpty {
                EmptyView()
            } else if mediaList.count == 1 {
                singleImageView(mediaList[0])
            } else if mediaList.count == 2 {
                twoImagesView(mediaList)
            } else {
                carouselStreamView(mediaList)
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - 1. Single Image (Exact Proportions based on Apple Hardware Physical Profile)
    private func singleImageView(_ media: TweetMedia) -> some View {
        let dims = calculateSingleDimensions(media)
        
        let card = ZStack {
            CachedAsyncImage(urlString: thumbUrl(media.mediaUrl), contentMode: .fill)
                .frame(width: dims.width, height: dims.height)
                .clipped()
            
            if media.isVideo {
                videoBadgeOverlay(for: media)
            }
        }
        .frame(width: dims.width, height: dims.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ThemeManager.border, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .overlay(
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if media.isVideo, let tweet = tweet {
                            VideoLightboxManager.shared.present(tweet: tweet, media: media)
                        } else {
                            let rect = proxy.frame(in: .global)
                            LightboxManager.shared.present(
                                mediaList: [media],
                                initialIndex: 0,
                                sourceRect: rect
                            )
                        }
                    }
            }
        )
        
        return HStack {
            card
            Spacer(minLength: 0)
        }
        .frame(height: dims.height)
    }
    
    private func calculateSingleDimensions(_ media: TweetMedia) -> (width: CGFloat, height: CGFloat) {
        // 读取当前 Apple 设备物理渲染分辨率的长宽各 1/2（转换为 points）
        let ref = AppleDisplayManager.shared.halfPhysicalReferencePoints
        let maxBoxW = min(layout.availableColumnWidth, ref.width)
        let maxBoxH = ref.height
        
        let rawRatio = media.aspectRatio > 0 ? media.aspectRatio : 1.0
        // 超长（大于 1:3 的长或宽图，允许缩放裁切到 1:3 比例）
        let clampedRatio = min(3.0, max(0.3333, rawRatio))
        let windowHeight = layout.windowHeight
        
        if clampedRatio < 1.0 {
            // 竖图 (Height > Width): 限制单个图片高度不得超过整个显示窗口的 1/3 高度并等比缩放
            let maxVerticalH = min(windowHeight / 3.0, maxBoxH)
            let h = maxVerticalH
            let w = min(maxBoxW, h * clampedRatio)
            return (w, h)
        } else {
            // 横图 (Width >= Height):
            // 比如 2560*1600 (16:10) 的非标准图片，在 maxBoxW * maxBoxH 内执行严格等比缩放 (Aspect Fit)：
            if maxBoxW / clampedRatio <= maxBoxH {
                // 宽度填满可用宽度，高度等比缩放
                let w = maxBoxW
                let h = w / clampedRatio
                return (w, h)
            } else {
                // 高度触顶，宽度等比缩放，剩余水平空间自然留白
                let h = maxBoxH
                let w = h * clampedRatio
                return (w, h)
            }
        }
    }
    
    // MARK: - 2. Two Images (Side-by-side, Left & Right rounded, exact height)
    private func twoImagesView(_ items: [TweetMedia]) -> some View {
        let availableWidth = layout.availableColumnWidth
        let spacing: CGFloat = 8
        let singleWidth = (availableWidth - spacing) / 2.0
        let height: CGFloat = min(layout.windowHeight / 3.0, 260)
        
        let card0 = ZStack {
            CachedAsyncImage(urlString: thumbUrl(items[0].mediaUrl), contentMode: .fill)
                .frame(width: singleWidth, height: height)
                .clipped()
            if items[0].isVideo {
                videoBadgeOverlay(for: items[0])
            }
        }
        .frame(width: singleWidth, height: height)
        .clipShape(RoundedCorner(tl: 16, tr: 0, bl: 16, br: 0))
        .overlay(
            RoundedCorner(tl: 16, tr: 0, bl: 16, br: 0)
                .stroke(ThemeManager.border, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .overlay(
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if items[0].isVideo, let tweet = tweet {
                            VideoLightboxManager.shared.present(tweet: tweet, media: items[0])
                        } else {
                            let rect = proxy.frame(in: .global)
                            LightboxManager.shared.present(mediaList: items, initialIndex: 0, sourceRect: rect)
                        }
                    }
            }
        )
        
        let card1 = ZStack {
            CachedAsyncImage(urlString: thumbUrl(items[1].mediaUrl), contentMode: .fill)
                .frame(width: singleWidth, height: height)
                .clipped()
            if items[1].isVideo {
                videoBadgeOverlay(for: items[1])
            }
        }
        .frame(width: singleWidth, height: height)
        .clipShape(RoundedCorner(tl: 0, tr: 16, bl: 0, br: 16))
        .overlay(
            RoundedCorner(tl: 0, tr: 16, bl: 0, br: 16)
                .stroke(ThemeManager.border, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .overlay(
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if items[1].isVideo, let tweet = tweet {
                            VideoLightboxManager.shared.present(tweet: tweet, media: items[1])
                        } else {
                            let rect = proxy.frame(in: .global)
                            LightboxManager.shared.present(mediaList: items, initialIndex: 1, sourceRect: rect)
                        }
                    }
            }
        )
        
        return HStack(spacing: spacing) {
            card0
            card1
        }
        .frame(width: availableWidth, height: height)
    }
    
    // MARK: - 3. Modern Stream / Horizontal Card Stream
    private func carouselStreamView(_ items: [TweetMedia]) -> some View {
        let height: CGFloat = min(layout.windowHeight / 3.0, 260)
        let cardWidth: CGFloat = 220
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<items.count, id: \.self) { idx in
                    let media = items[idx]
                    let isFirst = idx == 0
                    let isLast = idx == items.count - 1
                    
                    let tl: CGFloat = isFirst ? 16 : 0
                    let bl: CGFloat = isFirst ? 16 : 0
                    let tr: CGFloat = isLast ? 16 : 0
                    let br: CGFloat = isLast ? 16 : 0
                    
                    let card = ZStack {
                        CachedAsyncImage(urlString: thumbUrl(media.mediaUrl), contentMode: .fill)
                            .frame(width: cardWidth, height: height)
                            .clipped()
                        if media.isVideo {
                            videoBadgeOverlay(for: media)
                        }
                    }
                    .frame(width: cardWidth, height: height)
                    .clipShape(RoundedCorner(tl: tl, tr: tr, bl: bl, br: br))
                    .overlay(
                        RoundedCorner(tl: tl, tr: tr, bl: bl, br: br)
                            .stroke(ThemeManager.border, lineWidth: 0.6)
                    )
                    .contentShape(Rectangle())
                    .overlay(
                        GeometryReader { proxy in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if media.isVideo, let tweet = tweet {
                                        VideoLightboxManager.shared.present(tweet: tweet, media: media)
                                    } else {
                                        let rect = proxy.frame(in: .global)
                                        LightboxManager.shared.present(mediaList: items, initialIndex: idx, sourceRect: rect)
                                    }
                                }
                        }
                    )
                    
                    card
                }
            }
        }
        .frame(height: height)
    }
    
    // MARK: - Video Overlay Badges (Play button + Duration pill)
    private func videoBadgeOverlay(for media: TweetMedia) -> some View {
        ZStack {
            // Center Play Icon
            Circle()
                .fill(Color.black.opacity(0.60))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .offset(x: 1.5)
                )
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                .shadow(radius: 8)
            
            // Bottom Right Duration Pill
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if let durationStr = media.videoInfo?.formattedDuration, !durationStr.isEmpty {
                        Text(durationStr)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                            .padding(6)
                    } else if media.type == "animated_gif" {
                        Text("GIF")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                            .padding(6)
                    }
                }
            }
        }
    }
}
