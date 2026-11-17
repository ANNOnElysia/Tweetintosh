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
        let corner: CGFloat = isQuoted ? 10 : 16
        // Full bleed: the strip starts at the text column but its viewport is the whole row, so cards slide under the
        // window's edge. The leading and trailing values are what the row's 16pt margin, avatar and spacing hide.
        let bleeds = bleedsMedia && !isQuoted
        let leading: CGFloat = bleeds ? 66 + readingLeadingGutter : 0
        let trailing: CGFloat = bleeds ? 16 + readingTrailingGutter : 0

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: bleeds ? 8 : 2) {
                ForEach(0..<items.count, id: \.self) { idx in
                    let media = items[idx]
                    let ratio = media.aspectRatio > 0 ? media.aspectRatio : 1.0
                    let cardWidth = max(8, height * ratio)
                    let isFirst = idx == 0
                    let isLast = idx == items.count - 1
                    // A full-bleed strip has separate cards, like an album shelf; the inset strip stays one continuous row.
                    let shape = bleeds
                        ? RoundedCorner(tl: corner, tr: corner, bl: corner, br: corner)
                        : RoundedCorner(tl: isFirst ? corner : 0, tr: isLast ? corner : 0,
                                        bl: isFirst ? corner : 0, br: isLast ? corner : 0)

                    MediaTile(
                        media: media,
                        url: thumbUrl(media.mediaUrl),
                        size: CGSize(width: cardWidth, height: height),
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
            .background(ScrollViewAccessor { sv in HorizontalOnlyScrolling.shared.register(sv) })
            .background {
                if let onCarouselScroll {
                    CarouselScrollReporter(onOffset: onCarouselScroll)
                }
            }
        }
        // A reused table cell must not open the next post's images partway along
        .id(tweet?.id)
        .frame(height: height)
        // Negative padding widens the viewport back to the row; the cards themselves keep their size.
        .padding(.leading, -leading)
        .padding(.trailing, -trailing)
    }
}

// Reports the carousel's horizontal offset to the row, which uses it to move the avatar out of the way.
private struct CarouselScrollReporter: NSViewRepresentable {
    var onOffset: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onOffset = onOffset
        return view
    }

    func updateNSView(_ nsView: ReporterView, context: Context) {
        nsView.onOffset = onOffset
        nsView.attach()
    }

    final class ReporterView: NSView {
        var onOffset: ((CGFloat) -> Void)?
        private var token: NSObjectProtocol?
        private weak var clip: NSClipView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        func attach() {
            guard let scrollView = enclosingScrollView, clip !== scrollView.contentView else { return }
            detach()
            let clip = scrollView.contentView
            self.clip = clip
            clip.postsBoundsChangedNotifications = true
            token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                           object: clip, queue: .main) { [weak self] _ in
                guard let self, let clip = self.clip else { return }
                self.onOffset?(clip.bounds.minX)
            }
            onOffset?(clip.bounds.minX)
        }

        private func detach() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            clip = nil
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
