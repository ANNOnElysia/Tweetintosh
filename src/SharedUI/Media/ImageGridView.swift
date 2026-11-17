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

// MARK: - Photo Presentation Views (Proportional Scaling via Apple Hardware Resolution)
struct ImageGridView: View {
    let mediaList: [TweetMedia]
    var tweet: Tweet? = nil
    var isInteractive: Bool = true
    var isQuoted: Bool = false
    // In the Home timeline: the carousel may run past the reading column, out to the window's edge
    var bleedsMedia: Bool = false
    // Reports how far a full-bleed carousel has been scrolled, for the row's avatar to step out of the way
    var onCarouselScroll: ((CGFloat) -> Void)? = nil
    @ObservedObject var theme = ThemeManager.shared
    @Environment(\.mediaColumnWidth) private var mediaColumnWidth
    @Environment(\.readingLeadingGutter) private var readingLeadingGutter
    @Environment(\.readingTrailingGutter) private var readingTrailingGutter
    
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
        // Full bleed: the strip starts at the text column but its viewport is the whole row, so cards slide under the
        // window's edge. The leading and trailing values are what the row's 16pt margin, avatar and spacing hide.
        let bleeds = bleedsMedia && !isQuoted
        let leading: CGFloat = bleeds ? 66 + readingLeadingGutter : 0
        let trailing: CGFloat = bleeds ? 16 + readingTrailingGutter : 0

        return CarouselStrip(
            items: items,
            height: height,
            corner: isQuoted ? 10 : 16,
            bleeds: bleeds,
            leading: leading,
            trailing: trailing,
            tweet: tweet,
            isInteractive: isInteractive,
            onCarouselScroll: onCarouselScroll
        )
        // A reused table cell must not open the next post's images partway along, nor keep its paging state
        .id(tweet?.id)
    }
}

// The multi-image strip. Every card is as wide as its photo, so the strip runs past the column and the photos beyond
// the edge are otherwise reachable only by scrolling; a mouse has no two-finger swipe, so a pair of arrows fades in
// with the pointer and pages one card at a time.
private struct CarouselStrip: View {
    let items: [TweetMedia]
    let height: CGFloat
    let corner: CGFloat
    let bleeds: Bool
    let leading: CGFloat
    let trailing: CGFloat
    let tweet: Tweet?
    let isInteractive: Bool
    let onCarouselScroll: ((CGFloat) -> Void)?

    // Whether the strip can be paged at all, and which way, read from the scroll view itself: it is laid out wider
    // than the column, so these come from the scroll view's own range, not from this view's geometry. Booleans rather
    // than the offsets keep a scroll from redrawing the row on every frame of it.
    @State private var canScroll = false
    @State private var canPageBack = false
    @State private var canPageForward = false
    @State private var isPointerInside = false
    // The paging action needs the scroll view the SwiftUI view is drawn into; assigning into a reference holder keeps
    // it out of the view's own state.
    @State private var scrollRef = CarouselScrollViewRef()

    private var gap: CGFloat { bleeds ? 8 : 2 }

    private var cardWidths: [CGFloat] {
        items.map { max(8, height * ($0.aspectRatio > 0 ? $0.aspectRatio : 1.0)) }
    }

    /// Where each card starts, measured from the first card rather than from the content's edge, so a card at `0` is
    /// the one sitting at the text column and every other value is also the offset that pages it there.
    private var cardOffsets: [CGFloat] {
        var x: CGFloat = 0
        return cardWidths.map { width in
            defer { x += width + gap }
            return x
        }
    }

    private var showsArrows: Bool {
        isInteractive && canScroll
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: gap) {
                ForEach(0..<items.count, id: \.self) { idx in
                    let media = items[idx]
                    let isFirst = idx == 0
                    let isLast = idx == items.count - 1
                    // A full-bleed strip has separate cards, like an album shelf; the inset strip stays one continuous row.
                    let shape = bleeds
                        ? RoundedCorner(tl: corner, tr: corner, bl: corner, br: corner)
                        : RoundedCorner(tl: isFirst ? corner : 0, tr: isLast ? corner : 0,
                                        bl: isFirst ? corner : 0, br: isLast ? corner : 0)

                    MediaTile(
                        media: media,
                        url: MediaCacheManager.shared.formatThumbUrl(media.mediaUrl),
                        size: CGSize(width: cardWidths[idx], height: height),
                        shape: shape,
                        lightboxItems: items,
                        index: idx,
                        tweet: tweet,
                        isInteractive: isInteractive
                    )
                }
            }
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            // Inside the ScrollView, so the accessor finds the carousel's scroll view and not the timeline's
            .background(ScrollViewAccessor { sv in
                HorizontalOnlyScrolling.shared.register(sv)
                scrollRef.view = sv
            })
            .background {
                CarouselScrollReporter { offset, maxOffset in
                    canScroll = maxOffset > 0.5
                    canPageBack = offset > 0.5
                    canPageForward = offset < maxOffset - 0.5
                    onCarouselScroll?(offset)
                }
            }
        }
        .frame(height: height)
        // Negative padding widens the viewport back to the row; the cards themselves keep their size.
        .padding(.leading, -leading)
        .padding(.trailing, -trailing)
        // Over the column the post is read in, not over the whole window the strip bleeds out to.
        .overlay { pagingArrows }
        .onHover { isPointerInside = $0 }
    }

    @ViewBuilder private var pagingArrows: some View {
        if showsArrows {
            HStack {
                pagingButton(icon: "arrow.left", canPage: canPageBack) { page(backward: true) }
                Spacer()
                pagingButton(icon: "arrow.right", canPage: canPageForward) { page(backward: false) }
            }
            .padding(.horizontal, 10)
            .opacity(isPointerInside ? 1 : 0)
            .animation(.easeInOut(duration: 0.16), value: isPointerInside)
            .allowsHitTesting(isPointerInside)
        }
    }

    private func pagingButton(icon: String, canPage: Bool, action: @escaping () -> Void) -> some View {
        CarouselPagingButton(icon: icon, action: action)
            // An end of the strip keeps its arrow, at a third of its weight, so paging never moves the pair about.
            .opacity(canPage ? 1 : 0.32)
            .allowsHitTesting(canPage)
    }

    /// Pages to the next card still ahead of the column, and to the strip's end when there is no whole card left, which
    /// is how the last photo is reached even if it cannot be aligned to the column at all.
    private func page(backward: Bool) {
        guard let scrollView = scrollRef.view else { return }
        let clip = scrollView.contentView
        let offset = clip.bounds.minX
        let maxOffset = max(0, (scrollView.documentView?.frame.width ?? 0) - clip.bounds.width)
        let target = backward
            ? cardOffsets.last { $0 < offset - 1 } ?? 0
            : cardOffsets.first { $0 > offset + 1 } ?? maxOffset
        let destination = min(max(0, target), maxOffset)
        let origin = NSPoint(x: destination, y: clip.bounds.minY)

        scrollRef.pageToken += 1
        let token = scrollRef.pageToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(origin)
        }
        // AppKit only animates a window it draws: a page asked of a hidden or off-screen strip is put where it was
        // going without the glide, and a newer page cancels this one instead of dragging the strip back to it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            guard scrollRef.pageToken == token, scrollRef.view?.contentView === clip else { return }
            guard abs(clip.bounds.minX - destination) > 1 else { return }
            clip.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clip)
        }
    }
}

private final class CarouselScrollViewRef {
    weak var view: NSScrollView?
    var pageToken = 0
}

/// One arrow of the strip: a dark HUD disc with a white glyph, the same control the video viewer puts over its picture.
/// System glass was the first choice here and does not hold up: over a bright photo the disc turns nearly white and
/// takes the glyph with it, where this stays legible against any photograph.
private struct CarouselPagingButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background {
                    ZStack {
                        VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                        Color.black.opacity(0.45)
                    }
                    .clipShape(Circle())
                }
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.30), radius: 8, x: 0, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.target)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// Reports where the carousel is scrolled to and how much further it can go: the row uses the offset to move its
// avatar out of the way, and the paging arrows use both to know which ends are still out of reach.
private struct CarouselScrollReporter: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.onScroll = onScroll
        nsView.attach()
    }

    final class ReporterView: NSView {
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        private var tokens: [NSObjectProtocol] = []
        private weak var clip: NSClipView?
        private weak var document: NSView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        func attach() {
            guard let scrollView = enclosingScrollView, clip !== scrollView.contentView else { return }
            detach()
            let clip = scrollView.contentView
            self.clip = clip
            self.document = scrollView.documentView
            clip.postsBoundsChangedNotifications = true
            scrollView.documentView?.postsFrameChangedNotifications = true
            // The document's width is what the strip can be paged through, and it changes when the cards lay out.
            tokens.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                 object: clip, queue: .main) { [weak self] _ in
                self?.report()
            })
            tokens.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                                 object: scrollView.documentView, queue: .main) { [weak self] _ in
                self?.report()
            })
            report()
        }

        private func report() {
            guard let clip else { return }
            let maxOffset = max(0, (document?.frame.width ?? 0) - clip.bounds.width)
            onScroll?(clip.bounds.minX, maxOffset)
        }

        private func detach() {
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            tokens.removeAll()
            clip = nil
            document = nil
        }

        deinit { detach() }
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
    @ObservedObject private var theme = ThemeManager.shared
    
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
        // A tile opens the photo viewer or the video player, which is navigation, so it shows the hand; a quoted
        // card's media opens nothing and keeps the arrow.
        .navigationPointer(isInteractive)
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
