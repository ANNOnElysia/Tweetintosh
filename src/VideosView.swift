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
        .onAppear { feed.prepare() }
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
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                // A lazy stack builds the neighbours of the page on screen early, so the next video is already there
                // when the swipe lands
                let currentIndex = feed.currentIndex
                ForEach(Array(feed.posts.enumerated()), id: \.element.id) { index, post in
                    VideoPage(post: post, isCurrent: index == currentIndex,
                              isNeighbour: currentIndex.map { abs(index - $0) == 1 } ?? false)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(post.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $feed.currentID)
        .scrollIndicators(.hidden)
        .onChange(of: feed.currentID) { feed.didSettle() }
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
                ProgressView()
                    .controlSize(.regular)
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
        .buttonStyle(.plain)
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
            .buttonStyle(.plain)
            .help(loc.t("videos_open_profile"))

            if !post.displayBodyText.isEmpty {
                TweetText.text(post)
                    .font(theme.tweetFont(size: 14))
                    .lineLimit(3)
                    .handlesTweetLinks()
                    .textSelection(.enabled)
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
                    .buttonStyle(.plain)
                    .help(loc.t("share"))
                    .accessibilityLabel(loc.t("share"))
            }

            RailButton(
                title: loc.t("videos_open_post"),
                systemImage: "text.bubble",
                count: post.replyCount,
                effectTrigger: false
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
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                RailIcon(systemImage: systemImage, tint: tint, effectTrigger: effectTrigger)
            }
            .buttonStyle(.plain)
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
