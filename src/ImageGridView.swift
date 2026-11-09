//
//  ImageGridView.swift
//  Tweetintosh - Headless Data-driven Client
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
    // What to show, and the display box it was decoded for. A reused table cell keeps its loader for the next post, so
    // the two travel together: a box that no longer matches means the picture belongs to someone else.
    private struct Request: Equatable {
        let url: String
        let targetSize: CGSize?

        // Display box in device pixels; nil decodes at full resolution
        var pixelSize: CGSize? {
            guard let size = targetSize, size.width > 0, size.height > 0 else { return nil }
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            return CGSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        }
    }

    // Published as a CGImage so SwiftUI hands the decoded bitmap straight to Core Animation (no NSImage rep lookup)
    @Published private var loadedImage: CGImage?
    // The request the picture on screen belongs to, the one wanted now, and the one being fetched
    private var shown: Request?
    private var current: Request?
    private var inFlight: Request?

    init(urlString: String?, targetSize: CGSize? = nil) {
        guard let urlString = urlString else { return }
        let request = Request(url: urlString, targetSize: targetSize)
        current = request
        // Immediate frame-0 hit if already decoded in memory
        if let mem = MediaCacheManager.shared.memoryImage(for: urlString, targetPixelSize: request.pixelSize) {
            loadedImage = Self.cgImage(of: mem)
            shown = request
        }
    }

    // The picture for this address, or nil for the placeholder. Asked while the body is evaluated, so a reused cell never
    // shows the previous post's picture for even one frame, and so it must not change any published state.
    func image(urlString: String?, targetSize: CGSize?) -> CGImage? {
        guard let urlString = urlString else { return nil }
        let request = Request(url: urlString, targetSize: targetSize)
        if shown == request { return loadedImage }
        if let exact = MediaCacheManager.shared.memoryImage(for: urlString, targetPixelSize: request.pixelSize).flatMap(Self.cgImage(of:)) {
            return exact
        }
        // The same picture at another size (its tile is being resized) is drawn scaled until the right size is ready
        return shown?.url == urlString ? loadedImage : nil
    }

    func load(urlString: String?, targetSize: CGSize?) {
        guard let urlStr = urlString else {
            current = nil
            return
        }
        let request = Request(url: urlStr, targetSize: targetSize)
        current = request
        let targetPixelSize = request.pixelSize

        // 1. Memory cache hit -> synchronous frame-0 return without flicker
        if let mem = MediaCacheManager.shared.memoryImage(for: urlStr, targetPixelSize: targetPixelSize) {
            if shown != request || loadedImage == nil {
                loadedImage = Self.cgImage(of: mem)
                shown = request
            }
            return
        }
        
        // Only the size changed, as when the column is animating to a new width: the picture already decoded is drawn at
        // the new size meanwhile, and decoded again once, when the size has stopped changing, rather than on every frame
        if shown?.url == urlStr, loadedImage != nil {
            resizeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.current == request else { return }
                self.fetch(request)
            }
            resizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return
        }
        fetch(request)
    }

    private var resizeWork: DispatchWorkItem?

    private func fetch(_ request: Request) {
        let urlStr = request.url
        let targetPixelSize = request.pixelSize
        guard inFlight != request else { return }
        inFlight = request
        
        // 2. Offload disk lookup and network I/O to background queue to guarantee 120Hz smooth scrolling
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check disk cache first
            if let diskImg = MediaCacheManager.shared.diskImage(for: urlStr, targetPixelSize: targetPixelSize).flatMap(Self.cgImage(of:)) {
                DispatchQueue.main.async { self.finish(request, image: diskImg) }
                return
            }
            
            // 3. Network fetch
            guard let url = URL(string: urlStr) else {
                DispatchQueue.main.async { self.finish(request, image: nil) }
                return
            }
            
            let urlRequest = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            URLSession.shared.dataTask(with: urlRequest) { [weak self] data, _, _ in
                guard let self = self else { return }
                // Decode (and downsample) on this background thread to prevent main-thread decompression hitches
                let img = data.flatMap {
                    MediaCacheManager.shared.storeImageData($0, for: urlStr, targetPixelSize: targetPixelSize).flatMap(Self.cgImage(of:))
                }
                DispatchQueue.main.async { self.finish(request, image: img) }
            }.resume()
        }
    }
    
    private func finish(_ request: Request, image: CGImage?) {
        if inFlight == request { inFlight = nil }
        guard let image = image, current == request else { return }
        loadedImage = image
        shown = request
    }
    
    // Cache images are NSImage(cgImage:) wrappers, so this returns the backing CGImage without redrawing
    private static func cgImage(of image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

// MARK: - Cached Async Image View
struct CachedAsyncImage: View {
    private struct LoadKey: Equatable {
        let url: String?
        let targetSize: CGSize?
    }

    let urlString: String?
    var placeholderColor: Color = Color(white: 0.08)
    var contentMode: ContentMode = .fill
    let targetSize: CGSize?
    
    @StateObject private var loader: ImageLoader

    // targetSize (points): pass the on-screen box to decode a downsampled bitmap instead of the full image
    init(urlString: String?, placeholderColor: Color = Color(white: 0.08), contentMode: ContentMode = .fill, targetSize: CGSize? = nil) {
        self.urlString = urlString
        self.placeholderColor = placeholderColor
        self.contentMode = contentMode
        self.targetSize = targetSize
        _loader = StateObject(wrappedValue: ImageLoader(urlString: urlString, targetSize: targetSize))
    }
    
    var body: some View {
        ZStack {
            if let image = loader.image(urlString: urlString, targetSize: targetSize) {
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
            loader.load(urlString: urlString, targetSize: targetSize)
        }
        // The address can arrive after the view does (a profile opened from an @mention knows only the handle until
        // X has answered), and a reused table cell is handed a different post, so a new address is loaded too
        .onChange(of: LoadKey(url: urlString, targetSize: targetSize)) {
            loader.load(urlString: urlString, targetSize: targetSize)
        }
    }
}

// MARK: - Photo Presentation Views (Proportional Scaling via Apple Hardware Resolution)
struct ImageGridView: View {
    let mediaList: [TweetMedia]
    var tweet: Tweet? = nil
    var isInteractive: Bool = true
    var isQuoted: Bool = false
    @ObservedObject var theme = ThemeManager.shared
    @Environment(\.mediaColumnWidth) private var mediaColumnWidth
    
    private var columnWidth: CGFloat {
        Self.columnWidth(mediaColumnWidth: mediaColumnWidth)
    }
    
    private static func columnWidth(mediaColumnWidth: CGFloat?) -> CGFloat {
        max(180, min(mediaColumnWidth ?? .infinity, TimelineLayoutState.shared.availableColumnWidth))
    }
    
    // How tall this grid will be, without building it, for rows that need a height before they exist. The grid's sizes come
    // from these same calculations, so the two can't drift apart.
    static func contentHeight(mediaList: [TweetMedia], isQuoted: Bool, mediaColumnWidth: CGFloat?) -> CGFloat {
        guard let first = mediaList.first else { return 0 }
        let top: CGFloat = 4 // The grid's own top padding
        if mediaList.count == 1 {
            let width = columnWidth(mediaColumnWidth: mediaColumnWidth)
            return top + singleDimensions(first, columnWidth: width, isQuoted: isQuoted).height
        }
        return top + stripHeight(isQuoted: isQuoted)
    }
    
    private static func stripHeight(isQuoted: Bool) -> CGFloat {
        let windowHeight = TimelineLayoutState.shared.windowHeight
        return isQuoted ? min(windowHeight / 3.5, 180) : min(windowHeight / 3.0, 260)
    }
    
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
        let dims = Self.singleDimensions(media, columnWidth: columnWidth, isQuoted: isQuoted)
        let corner: CGFloat = isQuoted ? 10 : 16
        
        return HStack {
            MediaTile(
                media: media,
                url: thumbUrl(media.mediaUrl),
                size: CGSize(width: dims.width, height: dims.height),
                shape: RoundedCorner(tl: corner, tr: corner, bl: corner, br: corner),
                lightboxItems: [media],
                index: 0,
                tweet: tweet,
                isInteractive: isInteractive
            )
            Spacer(minLength: 0)
        }
        .frame(height: dims.height)
    }
    
    private static func singleDimensions(_ media: TweetMedia, columnWidth: CGFloat, isQuoted: Bool) -> (width: CGFloat, height: CGFloat) {
        let layout = TimelineLayoutState.shared
        // 读取当前 Apple 设备物理渲染分辨率的长宽各 1/2（转换为 points）
        let ref = AppleDisplayManager.shared.halfPhysicalReferencePoints
        let maxBoxW = min(isQuoted ? max(180, columnWidth - 24) : columnWidth, ref.width)
        // 引用帖严格限制最大高度小于主帖（主帖限制为 min(windowHeight/3.0, 260)），主帖单图默认保持物理分辨率参考高度
        let maxBoxH = isQuoted ? min(layout.windowHeight / 3.5, 200) : ref.height
        
        let rawRatio = media.aspectRatio > 0 ? media.aspectRatio : 1.0
        // 超长（大于 1:3 的长或宽图，允许缩放裁切到 1:3 比例）
        let clampedRatio = min(3.0, max(0.3333, rawRatio))
        let windowHeight = layout.windowHeight
        
        if clampedRatio < 1.0 {
            // 竖图 (Height > Width): 限制单个图片高度不得超过整个显示窗口的 1/3 (引用帖为 1/3.5) 高度并等比缩放
            let maxVerticalH = min(isQuoted ? windowHeight / 3.5 : windowHeight / 3.0, maxBoxH)
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
        let availableWidth = isQuoted ? max(180, columnWidth - 24) : columnWidth
        let spacing: CGFloat = 8
        let singleWidth = (availableWidth - spacing) / 2.0
        let height = Self.stripHeight(isQuoted: isQuoted)
        let size = CGSize(width: singleWidth, height: height)
        let corner: CGFloat = isQuoted ? 10 : 16
        
        return HStack(spacing: spacing) {
            MediaTile(media: items[0], url: thumbUrl(items[0].mediaUrl), size: size,
                      shape: RoundedCorner(tl: corner, tr: 0, bl: corner, br: 0),
                      lightboxItems: items, index: 0, tweet: tweet, isInteractive: isInteractive)
            MediaTile(media: items[1], url: thumbUrl(items[1].mediaUrl), size: size,
                      shape: RoundedCorner(tl: 0, tr: corner, bl: 0, br: corner),
                      lightboxItems: items, index: 1, tweet: tweet, isInteractive: isInteractive)
        }
        .frame(width: availableWidth, height: height)
    }
    
    // MARK: - 3. Modern Stream / Horizontal Card Stream
    private func carouselStreamView(_ items: [TweetMedia]) -> some View {
        let height = Self.stripHeight(isQuoted: isQuoted)
        let cardWidth: CGFloat = isQuoted ? 160 : 220
        let corner: CGFloat = isQuoted ? 10 : 16
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: isQuoted ? 8 : 10) {
                ForEach(0..<items.count, id: \.self) { idx in
                    let isFirst = idx == 0
                    let isLast = idx == items.count - 1
                    
                    MediaTile(
                        media: items[idx],
                        url: thumbUrl(items[idx].mediaUrl),
                        size: CGSize(width: cardWidth, height: height),
                        shape: RoundedCorner(tl: isFirst ? corner : 0, tr: isLast ? corner : 0, bl: isFirst ? corner : 0, br: isLast ? corner : 0),
                        lightboxItems: items,
                        index: idx,
                        tweet: tweet,
                        isInteractive: isInteractive
                    )
                }
            }
            // Inside the ScrollView, so the accessor finds the carousel's scroll view and not the timeline's
            .background(ScrollViewAccessor { sv in HorizontalOnlyScrolling.shared.register(sv) })
        }
        // A reused table cell must not open the next post's images partway along
        .id(tweet?.id)
        .frame(height: height)
    }
}

// MARK: - Horizontal-only Scrolling
// A horizontal ScrollView nested in the timeline keeps hold of vertical scroll gestures that start over it, so
// once the images have been scrolled sideways the timeline stops following the trackpad. A gesture that starts out
// mostly vertical over such a scroll view is handed to the enclosing scroll view instead, for its whole length
// (momentum included). Done with an event monitor: SwiftUI observes its scroll views, so they can't be subclassed.
final class HorizontalOnlyScrolling {
    static let shared = HorizontalOnlyScrolling()

    private let carousels = NSHashTable<NSScrollView>.weakObjects()
    private var monitor: Any?
    // Where the gesture in progress is being redirected, if it is
    private weak var redirectTarget: NSScrollView?

    func register(_ scrollView: NSScrollView) {
        carousels.add(scrollView)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let startsGesture = event.phase.contains(.began) || event.phase.contains(.mayBegin)
            || (event.phase.isEmpty && event.momentumPhase.isEmpty)
        if startsGesture {
            redirectTarget = nil
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let carousel = carousel(under: event) {
                redirectTarget = carousel.enclosingScrollView
            }
        }
        guard let target = redirectTarget else { return event }
        target.scrollWheel(with: event)
        return nil
    }

    private func carousel(under event: NSEvent) -> NSScrollView? {
        guard let window = event.window, let content = window.contentView, let frameView = content.superview else { return nil }
        // Bounds first: a mouse wheel comes here on every tick, and a hit test goes through SwiftUI's hit testing of every
        // row on screen. It is still needed when the pointer is over a carousel, in case something covers it.
        let isOverCarousel = carousels.allObjects.contains {
            $0.window === window && $0.convert($0.bounds, to: nil).contains(event.locationInWindow)
        }
        guard isOverCarousel else { return nil }
        var view = content.hitTest(frameView.convert(event.locationInWindow, from: nil))
        while let current = view {
            if let scrollView = current as? NSScrollView, carousels.contains(scrollView) { return scrollView }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Window-space Frame Holder
// Knows how to find where something is; read only when it is tapped, so scrolling does no work for it.
final class FrameBox: ObservableObject {
    // Outside a table cell: an AppKit view that marks the spot
    weak var view: NSView?
    // Inside one: the position relative to the cell, and the cell's hosting view to convert it
    fileprivate weak var cell: TableCellGeometry?
    fileprivate var cellFrame: CGRect = .zero

    // Where it really is, in the "AppWindow" space: read from AppKit, so it is right however a table has scrolled
    var liveRect: CGRect {
        guard let now = currentWindowRect(), let origin = AppWindowOrigin.windowRect else { return .zero }
        return CGRect(x: now.minX - origin.minX, y: origin.maxY - now.maxY, width: now.width, height: now.height)
    }

    private func currentWindowRect() -> CGRect? {
        if let host = cell?.hostView, host.window != nil { return host.convert(cellFrame, to: nil) }
        guard let view = view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }
}

// Lets a FrameBox find this view, in whichever way suits where the view is
struct LocatesFrame: ViewModifier {
    let box: FrameBox
    @Environment(\.tableCellGeometry) private var cell

    func body(content: Content) -> some View {
        if let cell = cell {
            content.onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(TableCellGeometry.spaceName))
            } action: { [box] frame in
                box.cell = cell
                box.cellFrame = frame
            }
        } else {
            content.background(FrameAnchor(box: box))
        }
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

struct FrameAnchor: NSViewRepresentable {
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
    var isInteractive: Bool = true
    
    @StateObject private var frameBox = FrameBox()
    
    var body: some View {
        ZStack {
            CachedAsyncImage(urlString: url, contentMode: .fill, targetSize: size)
                .frame(width: size.width, height: size.height)
                .clipped()
            if media.isVideo {
                VideoTileOverlay(media: media)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(
            shape.stroke(ThemeManager.border, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .modifier(LocatesFrame(box: frameBox))
        .overlay(
            Button(action: open) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.target)
            .disabled(!isInteractive)
        )
        .mediaContextMenu(media: media, tweet: tweet)
        .peekable(media.isVideo ? .video(media) : .image(media))
    }
    
    private func open() {
        guard isInteractive else { return }
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
struct VideoBadgeOverlay: View {
    let media: TweetMedia
    var showsPlayIcon: Bool = true
    
    var body: some View {
        ZStack {
            // Center Play Icon
            if showsPlayIcon {
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
            }
            
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
