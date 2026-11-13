//
//  VideosView.swift
//  Tweetintosh - Headless Data-driven Client
//
//  The Videos tab: X's recommended videos, one to a page, swiped through vertically.
//
//  An exception to the rule that scrolling screens are Lists: a List cannot snap to whole pages, and paging is the whole
//  point here (a flick always lands on exactly one video, never between two). So this is a ScrollView over a LazyVStack
//  with paging scroll behaviour. Each page is the size of the screen and only a few exist at a time, so the costs a List
//  avoids for long feeds of rows of varied height don't arise.
//

import SwiftUI
import AppKit

struct VideosView: View {
    @Bindable private var feed = VideosFeed.shared
    private let nav = NavigationManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    // How far a finger has dragged the page it is holding
    @State private var touchDrag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            if feed.posts.isEmpty {
                emptyState
            } else {
                pages
            }

            topEdge

            if nav.isVideosChromeHidden {
                sidebarButton
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        // Stop when the window is minimised or the app hidden, as a video player does. Another app merely being in
        // front leaves it playing.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            feed.isPlaying = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { note in
            if (note.object as? NSWindow) === NSApp.mainWindow { feed.isPlaying = false }
        }
    }

    private var pages: some View {
        // Pages are sized from the space the tab is given, not with containerRelativeFrame. A vertical scroll view takes
        // its width from its content, and content sized to the scroll view kept its old width when the window narrowed:
        // it held the scroll view open, pushing the sidebar off one edge and the action rail off the other.
        GeometryReader { geometry in
            let size = geometry.size
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    // Not lazy: a lazy stack only builds the next page once a swipe begins, too late for its video to be
                    // sitting on its first frame when the swipe lands. Only the pages near the one in view are real; the
                    // rest are black placeholders of the same size, so the feed's length costs next to nothing.
                    VStack(spacing: 0) {
                        let currentIndex = feed.currentIndex
                        ForEach(Array(feed.posts.enumerated()), id: \.element.id) { index, post in
                            let distance = currentIndex.map { abs(index - $0) } ?? index
                            Group {
                                if distance <= 2 {
                                    VideoPage(post: post, isCurrent: distance == 0, isNeighbour: distance == 1)
                                } else {
                                    Color.black
                                }
                            }
                            .frame(width: size.width, height: size.height)
                            .id(post.id)
                        }
                    }
                    .scrollTargetLayout()
                    .offset(y: touchDrag)
                    .background(ScrollViewAccessor { scrollView in
                        // A finger is paged by the drag below instead
                        if #available(macOS 27.0, *), scrollView.isTouchScrollingEnabled {
                            scrollView.isTouchScrollingEnabled = false
                        }
                    })
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $feed.currentID)
                .scrollIndicators(.hidden)
                .onChange(of: feed.currentID) { feed.didSettle() }
                // The pages change height with the window, and the scroll offset doesn't follow by itself: keep the
                // video being watched in place instead of landing between two
                .onChange(of: size) {
                    guard let id = feed.currentID else { return }
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { proxy.scrollTo(id, anchor: .top) }
                }
                .modifier(TouchPaging(offset: $touchDrag, pageHeight: size.height))
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        Group {
            if let reason = feed.emptyReason {
                Text(reason)
                    .font(theme.appFont(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                LoadingIndicator(compactHeight: 28, tint: .white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // The window's buttons, the sidebar button and the top bar float over the video, so its top edge is softened into a
    // blur that fades out downwards, as content scrolling under a toolbar is. Fixed in place over every page.
    private var topEdge: some View {
        // A SwiftUI material rather than an AppKit effect view, which a SwiftUI mask can't fade. It follows Reduce
        // Transparency by itself.
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.2))
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.35),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: Self.topEdgeHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let topEdgeHeight: CGFloat = 96

    // Below the window's buttons, where the top bar's own sidebar button would be
    private var sidebarButton: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                nav.sidebarExpanded = true
                nav.revealVideosChrome()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Circle()))
        }
        .buttonStyle(.target)
        .help(loc.t("videos_show_sidebar") + " (⌥`)")
        .accessibilityLabel(loc.t("videos_show_sidebar"))
        .padding(.leading, 16)
        .padding(.top, 44)
    }
}

// MARK: - Page

private struct VideoPage: View {
    let post: Tweet
    let isCurrent: Bool
    let isNeighbour: Bool
    private let feed = VideosFeed.shared
    private let nav = NavigationManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var isPlayerShowing = false

    private var isPlaying: Bool { isCurrent && feed.isPlaying }

    var body: some View {
        ZStack(alignment: .bottom) {
            video
                .contentShape(Rectangle())
                // A double tap likes the video, as on a phone, and a second one takes the like back; the heart on the
                // rail shows it. Declared first, so a single tap waits the moment it takes to tell the two apart.
                .onTapGesture(count: 2) { TweetActions().like(post) }
                .onTapGesture { feed.togglePlayback() }

            if isCurrent && !feed.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 1.3)))
                    .accessibilityHidden(true)
            }

            // A scrim keeps white text legible over any frame without boxing it in
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 16) {
                caption
                Spacer(minLength: 0)
                VideoActionRail(post: post)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .animation(VideosFeed.pageAnimation ?? .default, value: feed.isPlaying)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(post.author.name): \(post.displayBodyText)")
        .accessibilityAction(named: loc.t("videos_next")) { feed.move(by: 1) }
        .accessibilityAction(named: loc.t("videos_previous")) { feed.move(by: -1) }
        .accessibilityAction(named: loc.t(isPlaying ? "videos_pause" : "videos_play")) { feed.togglePlayback() }
    }

    @ViewBuilder private var video: some View {
        if let media = post.feedVideo {
            ZStack {
                // The still until the first frame is ready, letterboxed the same way the player will be
                if !isPlayerShowing {
                    CachedAsyncImage(urlString: media.mediaUrl, placeholderColor: .black, contentMode: .fit)
                }
                AutoplayVideoRepresentable(
                    media: media,
                    scope: .videos,
                    isPreferred: isCurrent,
                    isMuted: feed.isMuted,
                    showsWholeFrame: true,
                    isHeld: !isPlaying,
                    preloads: isNeighbour
                ) { playing in
                    DispatchQueue.main.async { isPlayerShowing = playing }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.black
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                nav.openProfile(post.author)
            } label: {
                HStack(spacing: 8) {
                    CachedAsyncImage(urlString: post.author.avatarUrl, targetSize: CGSize(width: 32, height: 32))
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(post.author.name)
                            .font(theme.appFont(size: 14, weight: .semibold))
                        Text(post.author.formattedHandle)
                            .font(theme.appFont(size: 12))
                            .opacity(0.8)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.target)
            .navigationPointer()
            .help(loc.t("videos_open_profile"))

            if !post.displayBodyText.isEmpty {
                TweetText.text(post)
                    .font(theme.tweetFont(size: 14))
                    .lineLimit(3)
                    .handlesTweetLinks()
                    .textSelection(.enabled)
                    .tweetLinkPointer(of: post, fontSize: 14, lineSpacing: 0, selectable: true)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 4)
        .frame(maxWidth: 520, alignment: .leading)
    }
}

// MARK: - Action Rail

private struct VideoActionRail: View {
    let post: Tweet
    private let feed = VideosFeed.shared
    private let nav = NavigationManager.shared
    private let actions = TweetActions()
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 14) {
            RailButton(
                title: loc.t(post.isFavorited ? "unlike" : "like"),
                systemImage: post.isFavorited ? "heart.fill" : "heart",
                count: post.favoriteCount,
                tint: post.isFavorited ? TweetActionBar.likeColor : .white,
                effectTrigger: post.isFavorited
            ) { actions.like(post) }

            RailButton(
                title: loc.t(post.isRetweeted ? "undo_retweet" : "retweet"),
                systemImage: "arrow.2.squarepath",
                count: post.retweetCount,
                tint: post.isRetweeted ? TweetActionBar.repostColor : .white,
                effectTrigger: post.isRetweeted
            ) { actions.repost(post) }

            RailButton(
                title: loc.t(post.isBookmarked ? "remove_bookmark" : "bookmark"),
                systemImage: post.isBookmarked ? "bookmark.fill" : "bookmark",
                tint: post.isBookmarked ? ThemeManager.accent : .white,
                effectTrigger: post.isBookmarked
            ) { actions.bookmark(post) }

            if let url = URL(string: "https://x.com/\(post.author.screenName)/status/\(post.id)") {
                ShareLink(item: url) { RailIcon(systemImage: "square.and.arrow.up") }
                    .buttonStyle(.target)
                    .help(loc.t("share"))
                    .accessibilityLabel(loc.t("share"))
            }

            RailButton(
                title: loc.t("videos_open_post"),
                systemImage: "text.bubble",
                count: post.replyCount,
                effectTrigger: false,
                opensPage: true
            ) { nav.openTweetDetail(post) }

            RailButton(
                title: loc.t(feed.isMuted ? "videos_unmute" : "videos_mute"),
                systemImage: feed.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                effectTrigger: feed.isMuted
            ) { feed.isMuted.toggle() }
        }
    }
}

private struct RailButton: View {
    let title: String
    let systemImage: String
    var count: Int?
    var tint: Color = .white
    var effectTrigger: Bool
    // Opens a page rather than acting in place, so it gets the hand; the count below is not part of the button
    var opensPage = false
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                RailIcon(systemImage: systemImage, tint: tint, effectTrigger: effectTrigger)
            }
            .buttonStyle(.target)
            .navigationPointer(opensPage)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityValue(count.map { $0.formatted() } ?? "")

            if let count, count > 0 {
                Text(count.formatted(.number.notation(.compactName)))
                    .font(theme.appFont(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct RailIcon: View {
    let systemImage: String
    var tint: Color = .white
    var effectTrigger = false

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: effectTrigger)
            .frame(width: 44, height: 44)
            .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Circle()))
    }
}

// MARK: - Touch Paging

// Paging scroll behaviour snaps a trackpad's swipe, but a finger's flick ran on through video after video and then
// drifted slowly into place. So on a touch screen the scroll view leaves fingers alone and this pages them itself: the
// video follows the finger 1:1, resists at either end of the feed, and on release springs quickly to the next or
// previous video, or back, as a phone's video feed does. Trackpad swipes and the keyboard still go through the scroll view.
private struct TouchPaging: ViewModifier {
    @Binding var offset: CGFloat
    let pageHeight: CGFloat
    private let feed = VideosFeed.shared

    // Any input, not only direct touch: with the scroll view's touch scrolling off, macOS hands a finger's drag to the
    // app as a mouse drag. A mouse can now drag a page too, which is harmless; a trackpad's two-finger swipe is a scroll,
    // not a drag, and still goes through the scroll view.
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .local)
                    .onChanged { drag(by: $0.translation.height) }
                    .onEnded { release(with: $0) }
            )
    }

    private func drag(by translation: CGFloat) {
        guard let index = feed.currentIndex else { return }
        // Pulling past the first or last video only gives a little, like a rubber band
        let atEnd = (translation > 0 && index == 0) || (translation < 0 && index == feed.posts.count - 1)
        offset = atEnd ? translation * 0.3 : translation
    }

    private func release(with value: DragGesture.Value) {
        guard let index = feed.currentIndex, pageHeight > 0 else { offset = 0; return }
        // Where the flick would carry the page if let go, so a short fast flick turns it as a long slow drag does
        let projected = value.predictedEndTranslation.height
        var step = 0
        if projected < -pageHeight * 0.3 || value.translation.height < -pageHeight * 0.5 { step = 1 }
        if projected > pageHeight * 0.3 || value.translation.height > pageHeight * 0.5 { step = -1 }
        let target = min(max(index + step, 0), feed.posts.count - 1)
        if target != index {
            // The scroll view moves to the new page at once, and the drag offset takes up the difference so nothing
            // on screen moves; only the offset is then animated. Animating the scroll position alongside it let the
            // two run out of step, and the page jumped before it slid.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                offset += CGFloat(target - index) * pageHeight
                feed.currentID = feed.posts[target].id
            }
        }
        withAnimation(Self.settle) { offset = 0 }
    }

    // Quick, with a hint of overshoot so the page lands rather than stops. None with Reduce Motion.
    private static var settle: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82)
    }
}
