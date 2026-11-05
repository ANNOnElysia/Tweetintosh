//
//  NotificationsView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

// MARK: - Isolated 120Hz Notifications Pull-to-Refresh Indicator Overlay
private struct NotificationsPullRefreshIndicatorOverlay: View {
    @ObservedObject var scrollState = TimelineScrollState.shared
    @ObservedObject var viewModel = NotificationsViewModel.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var nav = NavigationManager.shared
    
    var body: some View {
        if viewModel.isRefreshing || scrollState.pullDistance > 2.0 {
            let baseTop: CGFloat = nav.sidebarExpanded ? 36 : 118
            let pullDist = viewModel.isRefreshing ? 40.0 : scrollState.pullDistance
            let pullProg: CGFloat = viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, pullDist / TrackpadPullCoordinator.refreshThreshold))
            let opac: Double = viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, Double(pullDist - 2.0) / 8.0))
            let offsetY: CGFloat = baseTop + (pullDist - 40.0) / 2.0
            
            SVGRefreshIndicatorView(
                pullProgress: pullProg,
                isRefreshing: viewModel.isRefreshing,
                colorScheme: theme.themeColor
            )
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .offset(y: offsetY)
            .opacity(opac)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

struct NotificationsView: View {
    @ObservedObject var viewModel = NotificationsViewModel.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared

    var onOpenSettings: () -> Void = {}
    var onLoginRequest: () -> Void = {}
    
    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()
            
            // Notifications Scrollable Content
            notificationsContent
            
            // Secondary Floating Capsule: Filter Bar (All / Likes & Reposts / Comments / Mentions)
            // Dual-Mode (Liquid Glass vs Frosted Glass)
            // With the sidebar open the same filters sit under Notifications in the sidebar instead
            if !nav.sidebarExpanded {
                NotificationFilterCapsuleBar()
                    .padding(.top, 62)
                    .zIndex(50)
            }
        }
        .onAppear {
            TrackpadPullCoordinator.shared.onPullProgress = { distance in
                TimelineScrollState.shared.pullDistance = distance
                TimelineScrollState.shared.isPullThresholdExceeded = (distance >= TrackpadPullCoordinator.refreshThreshold)
            }
            TrackpadPullCoordinator.shared.onTriggerRefresh = {
                TimelineScrollState.shared.isPullThresholdExceeded = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    TimelineScrollState.shared.pullDistance = 0
                }
                viewModel.refresh(silently: false)
            }
            TrackpadPullCoordinator.shared.onCancelPull = {
                TimelineScrollState.shared.isPullThresholdExceeded = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    TimelineScrollState.shared.pullDistance = 0
                }
            }
            TrackpadPullCoordinator.shared.startMonitoring(owner: "Notifications")
        }
        .onDisappear {
            TrackpadPullCoordinator.shared.stopMonitoring(owner: "Notifications")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_RefreshTimeline"))) { _ in
            if nav.currentTab == .notifications && !nav.hasOverlay {
                viewModel.refresh(silently: false)
            }
        }
    }
    
    // MARK: - Notifications Scroll Content
    private var notificationsContent: some View {
        ScrollViewReader { scrollProxy in
            // Clearance under top capsules (Primary Capsule + Secondary Filter Capsule)
            // During refreshing, expands by 40pt so items stay pushed down for the 40pt animation area!
            ScrollContainer(
                topSpacer: (nav.sidebarExpanded ? 36 : 118) + (viewModel.isRefreshing ? 40 : 0),
                onScrollView: { sv in
                    TrackpadPullCoordinator.shared.attachScrollView(sv, owner: "Notifications")
                },
                onNearBottom: { viewModel.loadMore() }
            ) {
                    
                    // Items List or Empty Placeholder
                    if viewModel.isLoadingSelectedFeed {
                        GrowingArcIndicator(color: ThemeManager.accent, lineWidth: 1.5, size: 20)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if viewModel.filteredItems.isEmpty {
                        emptyFilterView
                    } else {
                        ForEach(viewModel.filteredItems) { item in
                            // Row and its divider in one view: a 0.5pt divider on its own would be padded to a full
                            // row height in a List
                            VStack(spacing: 0) {
                                NotificationRowView(item: item)
                                
                                // Subtle divider separating notification items (matching Home)
                                Rectangle()
                                    .fill(ThemeManager.divider)
                                    .frame(height: 0.5)
                            }
                            .id(item.id)
                        }
                    }
                    
                    // Bottom Spacer
                    Color.clear
                        .frame(height: 40)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isRefreshing)
            .coordinateSpace(name: "notifScrollViewSpace")
            .environment(\.peekScope, .notifications)
            .overlay(alignment: .top) {
                NotificationsPullRefreshIndicatorOverlay()
            }
        }
    }
    
    // MARK: - Empty Filter View
    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.selectedFilter.iconName)
                .font(.system(size: 34))
                .foregroundColor(ThemeManager.tertiaryText)
                .padding(.top, 40)
            
            Text(loc.t("empty_notifications"))
                .font(.system(size: 13.5))
                .foregroundColor(ThemeManager.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Secondary Floating Filter Capsule Bar (Dual-Mode Liquid Glass)
private struct NotificationFilterCapsuleBar: View {
    @ObservedObject var viewModel = NotificationsViewModel.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var filterTabNamespace
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(NotificationFilter.allCases) { filter in
                let isSelected = viewModel.selectedFilter == filter
                Button {
                    viewModel.selectFilter(filter)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.iconName)
                            .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                        
                        if nav.showShortcutBadges {
                            // Shortcut Indicator (⌥Q, ⌥W, ⌥E, ⌥R)
                            Text(filter.shortcutKey)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? ThemeManager.accent.opacity(0.9) : (theme.isLight ? ThemeManager.tertiaryText : Color.white.opacity(0.40)))
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(isSelected ? ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.16) : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06)))
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .foregroundColor(isSelected ? ThemeManager.accent : (theme.isLight ? ThemeManager.primaryText.opacity(0.68) : Color.white.opacity(0.70)))
                    .frame(height: 26)
                    .frame(minWidth: nav.showShortcutBadges ? 46 : 32)
                    .padding(.horizontal, nav.showShortcutBadges ? 6 : 4)
                    .background {
                        if isSelected {
                            activeFilterBackground
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .help(loc.t(filter.titleKey))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3.5)
        .modifier(
            AdaptiveGlassModifier(
                isLiquid: theme.useLiquidGlass,
                shape: Capsule()
            )
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: nav.showShortcutBadges)
        .fixedSize()
    }
    
    @ViewBuilder
    private var activeFilterBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : (theme.isLight ? Color.black : Color.white)
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.20))
                    : .regular
                Capsule()
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? (theme.isLight ? 0.14 : 0.22) : (theme.isLight ? 0.08 : 0.14)))
                    .tweetGlass(tabGlass, in: Capsule())
                    .matchedGeometryEffect(id: "notif-active-filter", in: filterTabNamespace)
            } else {
                defaultActiveBackground
            }
        } else {
            defaultActiveBackground
        }
    }
    
    private var defaultActiveBackground: some View {
        Capsule()
            .fill(theme.isLight ? ThemeManager.accent.opacity(0.18) : ThemeManager.accent.opacity(0.26))
            .overlay(
                Capsule()
                    .stroke(theme.isLight ? ThemeManager.accent.opacity(0.35) : Color.white.opacity(0.22), lineWidth: 0.7)
                    .allowsHitTesting(false)
            )
            .matchedGeometryEffect(id: "notif-active-filter", in: filterTabNamespace)
    }
}

// MARK: - Avatar Pile

/// Up to four of the people behind a notification, overlapping with the first on top. Clicking one opens their profile
/// and a deep press previews it.
private struct NotificationAvatarPile: View {
    let actors: [TweetUser]

    private static let size: CGFloat = 26
    private static let overlap: CGFloat = 8

    var body: some View {
        let shown = Array(actors.prefix(4))
        HStack(spacing: -Self.overlap) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, actor in
                CachedAsyncImage(urlString: actor.avatarUrl, targetSize: CGSize(width: Self.size, height: Self.size))
                    .frame(width: Self.size, height: Self.size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ThemeManager.background, lineWidth: shown.count > 1 ? 1.5 : 0))
                    // A press finds its target by frame, so each one claims only the part of it that is visible
                    .overlay(alignment: .trailing) {
                        Color.clear
                            .frame(width: index == 0 ? Self.size : Self.size - Self.overlap)
                            .peekable(.profile(actor))
                    }
                    .opensProfile(actor)
                    .zIndex(Double(shown.count - index))
            }
        }
    }
}

// MARK: - Individual Notification Row View
private struct NotificationRowView: View {
    var item: NotificationItem
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    
    // "9 others" in a like or repost summary opens the list of people; the phrase differs by language
    private static let othersPatterns = [#"\d+ others"#, #"他\d+人"#, #"외 \d+명"#, #"\d+ 人"#]
    
    private var summaryText: AttributedString {
        let summary = item.localizedActionSummary
        var text = AttributedString(summary)
        guard (item.type == .like || item.type == .retweet), let tweetId = item.targetTweetId else { return text }
        let kind = item.type == .like ? "likes" : "reposts"
        for pattern in Self.othersPatterns {
            if let range = summary.range(of: pattern, options: .regularExpression),
               let attrRange = Range(range, in: text),
               let url = URL(string: "tweetintosh://users/\(kind)/\(tweetId)") {
                text[attrRange].link = url
                text[attrRange].foregroundColor = ThemeManager.accent
                return text
            }
        }
        return text
    }
    
    // Clicking a notification opens the post it is about
    private func openTargetPost() {
        guard let tweetId = item.targetTweetId else { return }
        let account = AccountManager.shared.active
        let me = TweetUser(id: account?.id ?? "", name: account?.name ?? "", screenName: account?.screenName ?? "",
                           avatarUrl: account?.avatarUrl, isVerified: false)
        // Only what the notification knows; the page fetches the rest
        let stub = Tweet(id: tweetId, text: item.targetTweetSnippet ?? "", createdAt: item.createdAt, author: me, media: [],
                         replyCount: 0, retweetCount: 0, favoriteCount: 0, isRetweet: false, retweetedBy: nil)
        NavigationManager.shared.openTweetDetail(stub)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: Type Icon Badge (Heart, Retweet, Reply, Mention, or Recent Post)
            let isRecent = item.isRecentPost
            let badgeColor = isRecent ? Color(red: 0.11, green: 0.61, blue: 0.94) : item.type.accentColor
            let badgeIcon = isRecent ? "sparkles" : item.type.iconName
            
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.18))
                    .frame(width: 32, height: 32)
                
                Image(systemName: badgeIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(badgeColor)
            }
            .padding(.top, 2)
            
            // Center Content, then the post's picture on the right
            VStack(alignment: .leading, spacing: 6) {
                // Actor Avatar(s) & Timestamp
                HStack(alignment: .center, spacing: 8) {
                    if item.actors.isEmpty {
                        Circle()
                            .fill(theme.isLight ? Color.black.opacity(0.08) : Color(white: 0.16))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.7))
                            )
                    } else {
                        NotificationAvatarPile(actors: item.actors)
                    }
                    
                    // Summary text
                    Text(summaryText)
                        .handlesTweetLinks()
                        .font(theme.appFont(size: 13, weight: .semibold))
                        .foregroundColor(ThemeManager.primaryText)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Relative Time
                    Text(item.relativeTime)
                        .font(theme.appFont(size: 12))
                        .foregroundColor(ThemeManager.tertiaryText)
                }
                
                // Reply/Comment body if applicable
                if let reply = item.replyBody {
                    Text(reply)
                        .font(theme.tweetFont(size: 13.5))
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText.opacity(0.92) : Color.white.opacity(0.85))
                        .padding(.vertical, 2)
                }
                
                // Quoted/Target Tweet Excerpt Card
                if let targetSnippet = item.targetTweetSnippet {
                    Text(targetSnippet)
                        .font(theme.tweetFont(size: 12.5))
                        .foregroundColor(ThemeManager.secondaryText)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ThemeManager.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(ThemeManager.border, lineWidth: 0.6)
                                )
                        )
                }
            }
            
            if let thumbnail = item.thumbnailUrl {
                CachedAsyncImage(urlString: thumbnail, placeholderColor: ThemeManager.cardBackground, targetSize: CGSize(width: 64, height: 64))
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ThemeManager.border, lineWidth: 0.6))
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { openTargetPost() }
    }
}
