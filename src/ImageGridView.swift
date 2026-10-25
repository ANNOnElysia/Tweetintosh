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
    
    private init() {}
    
    func image(for url: String) -> NSImage? {
        MediaCacheManager.shared.image(for: url)
    }
    
    func setImage(_ image: NSImage, for url: String) {
        MediaCacheManager.shared.storeImage(image, rawData: nil, for: url)
    }
    
    func prefetch(urls: [String]) {
        MediaCacheManager.shared.prefetchImages(urls: urls)
    }
}

// MARK: - Image Loader (Sync Cache Hit & Offloaded Disk/Network)
final class ImageLoader: ObservableObject {
    // Published as a CGImage so SwiftUI hands the decoded bitmap straight to Core Animation (no NSImage rep lookup)
    @Published var loadedImage: CGImage?
    @Published var isLoading = false
    private var currentUrl: String?
    // Display box in device pixels; nil decodes at full resolution
    private let targetPixelSize: CGSize?

    init(urlString: String?, targetSize: CGSize? = nil) {
        self.currentUrl = urlString
        if let size = targetSize, size.width > 0, size.height > 0 {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            self.targetPixelSize = CGSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        } else {
            self.targetPixelSize = nil
        }
        if let urlStr = urlString {
            // Immediate frame-0 hit if already decoded in memory
            if let mem = MediaCacheManager.shared.memoryImage(for: urlStr, targetPixelSize: targetPixelSize) {
                self.loadedImage = Self.cgImage(of: mem)
            }
        }
    }

    func load(urlString: String?) {
        guard let urlStr = urlString else { return }
        self.currentUrl = urlStr
        let targetPixelSize = self.targetPixelSize

        // 1. Memory cache hit -> synchronous frame-0 return without flicker
        if let mem = MediaCacheManager.shared.memoryImage(for: urlStr, targetPixelSize: targetPixelSize) {
            if self.loadedImage == nil {
                self.loadedImage = Self.cgImage(of: mem)
            }
            return
        }
        
        guard !isLoading else { return }
        isLoading = true
        
        // 2. Offload disk lookup and network I/O to background queue to guarantee 120Hz smooth scrolling
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check disk cache first
            if let diskImg = MediaCacheManager.shared.diskImage(for: urlStr, targetPixelSize: targetPixelSize).flatMap(Self.cgImage(of:)) {
                DispatchQueue.main.async {
                    if self.currentUrl == urlStr {
                        self.loadedImage = diskImg
                    }
                    self.isLoading = false
                }
                return
            }
            
            // 3. Network fetch
            guard let url = URL(string: urlStr) else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
                guard let self = self else { return }
                // Decode (and downsample) on this background thread to prevent main-thread decompression hitches
                if let data = data,
                   let img = MediaCacheManager.shared.storeImageData(data, for: urlStr, targetPixelSize: targetPixelSize).flatMap(Self.cgImage(of:)) {
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
    
    // Cache images are NSImage(cgImage:) wrappers, so this returns the backing CGImage without redrawing
    private static func cgImage(of image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

// MARK: - Cached Async Image View
struct CachedAsyncImage: View {
    let urlString: String?
    var placeholderColor: Color = Color(white: 0.08)
    var contentMode: ContentMode = .fill
    
    @StateObject private var loader: ImageLoader

    // targetSize (points): pass the on-screen box to decode a downsampled bitmap instead of the full image
    init(urlString: String?, placeholderColor: Color = Color(white: 0.08), contentMode: ContentMode = .fill, targetSize: CGSize? = nil) {
        self.urlString = urlString
        self.placeholderColor = placeholderColor
        self.contentMode = contentMode
        _loader = StateObject(wrappedValue: ImageLoader(urlString: urlString, targetSize: targetSize))
    }
    
    var body: some View {
        ZStack {
            if let image = loader.loadedImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                // Plain placeholder: a ProgressView here is an AppKit NSProgressIndicator per loading tile, and
                // creating/animating one for every image scrolling into view caused visible scroll hitches.
                Rectangle()
                    .fill(placeholderColor)
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
        
        return HStack {
            MediaTile(
                media: media,
                url: thumbUrl(media.mediaUrl),
                size: CGSize(width: dims.width, height: dims.height),
                shape: RoundedCorner(tl: 16, tr: 16, bl: 16, br: 16),
                lightboxItems: [media],
                index: 0,
                tweet: tweet
            )
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
        let size = CGSize(width: singleWidth, height: height)
        
        return HStack(spacing: spacing) {
            MediaTile(media: items[0], url: thumbUrl(items[0].mediaUrl), size: size,
                      shape: RoundedCorner(tl: 16, tr: 0, bl: 16, br: 0),
                      lightboxItems: items, index: 0, tweet: tweet)
            MediaTile(media: items[1], url: thumbUrl(items[1].mediaUrl), size: size,
                      shape: RoundedCorner(tl: 0, tr: 16, bl: 0, br: 16),
                      lightboxItems: items, index: 1, tweet: tweet)
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
                    let isFirst = idx == 0
                    let isLast = idx == items.count - 1
                    
                    MediaTile(
                        media: items[idx],
                        url: thumbUrl(items[idx].mediaUrl),
                        size: CGSize(width: cardWidth, height: height),
                        shape: RoundedCorner(tl: isFirst ? 16 : 0, tr: isLast ? 16 : 0, bl: isFirst ? 16 : 0, br: isLast ? 16 : 0),
                        lightboxItems: items,
                        index: idx,
                        tweet: tweet
                    )
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Window-space Frame Holder
// Written on every geometry change without invalidating any view (no @Published); read only when a tile is tapped.
private final class FrameBox: ObservableObject {
    var rect: CGRect = .zero
    // SwiftUI's reported frame goes stale while a List scrolls (the table moves its clip view, not the SwiftUI
    // layout). The tile's AppKit view always knows where it really is, so the reported frame is shifted by how
    // far that view has moved since the frame was reported.
    weak var view: NSView?

    func report(_ rect: CGRect) {
        self.rect = rect
    }

    // Where the tile really is, in the "AppWindow" space: read from AppKit, so it is right however a List has
    // scrolled and whatever offset it applies to the positions SwiftUI reports
    var liveRect: CGRect {
        guard let now = currentWindowRect(), let origin = AppWindowOrigin.windowRect else { return rect }
        return CGRect(x: now.minX - origin.minX, y: origin.maxY - now.maxY, width: now.width, height: now.height)
    }

    private func currentWindowRect() -> CGRect? {
        guard let view = view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }
}

// The "AppWindow" coordinate space starts at the top-left of the root view; this finds where that is on screen
enum AppWindowOrigin {
    fileprivate static weak var view: NSView?
    
    static var windowRect: CGRect? {
        guard let view = view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }
    
    struct Anchor: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            AppWindowOrigin.view = view
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {
            AppWindowOrigin.view = view
        }
    }
}

private struct FrameAnchor: NSViewRepresentable {
    let box: FrameBox
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}

// MARK: - Media Tile (image + video badge + tap-to-open lightbox)
private struct MediaTile: View {
    let media: TweetMedia
    let url: String
    let size: CGSize
    let shape: RoundedCorner
    let lightboxItems: [TweetMedia]
    let index: Int
    let tweet: Tweet?
    
    @StateObject private var frameBox = FrameBox()
    
    var body: some View {
        ZStack {
            CachedAsyncImage(urlString: url, contentMode: .fill, targetSize: size)
                .frame(width: size.width, height: size.height)
                .clipped()
            if media.isVideo {
                VideoBadgeOverlay(media: media)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(
            shape.stroke(ThemeManager.border, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        // onGeometryChange instead of a GeometryReader overlay: scrolling moves the frame every frame, and a
        // GeometryReader would rebuild the button and context menu each time; this only updates the box.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("AppWindow"))
        } action: { [frameBox] rect in
            frameBox.report(rect)
        }
        .background(FrameAnchor(box: frameBox))
        .overlay(
            Button(action: open) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        )
        .mediaContextMenu(media: media, tweet: tweet)
        .peekable(media.isVideo ? .video(media) : .image(media))
    }
    
    private func open() {
        let rect = frameBox.liveRect
        if media.isVideo, let tweet = tweet {
            VideoLightboxManager.shared.present(tweet: tweet, media: media)
        } else {
            MediaFrameRegistry.shared.register(key: media.mediaUrl, frame: rect)
            MediaFrameRegistry.shared.register(key: media.id, frame: rect)
            let box = frameBox
            let provider: () -> CGRect? = { [weak box] in box?.liveRect }
            MediaFrameRegistry.shared.register(key: media.mediaUrl, provider: provider)
            MediaFrameRegistry.shared.register(key: media.id, provider: provider)
            LightboxManager.shared.present(mediaList: lightboxItems, initialIndex: index, sourceRect: rect, tweet: tweet)
        }
    }
}

// MARK: - Video Overlay Badges (Play button + Duration pill)
private struct VideoBadgeOverlay: View {
    let media: TweetMedia
    
    var body: some View {
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
