//
//  TimelineView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI

// MARK: - Scroll Offset Tracker for Pull-to-Refresh
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

final class TimelineScrollState: ObservableObject {
    static let shared = TimelineScrollState()
    @Published var pullDistance: CGFloat = 0.0
    @Published var isPullThresholdExceeded: Bool = false
    @Published var isAtTop: Bool = true
    var hasTriggeredHaptic: Bool = false
}

// MARK: - Native NSScrollView Anchor & Viewport Coordinator
class CustomAnchorNSView: NSView {
    var onFound: ((NSScrollView) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let sv = enclosingScrollView { onFound?(sv) }
    }
}

struct ScrollViewAccessor: NSViewRepresentable {
    var onScrollView: (NSScrollView) -> Void
    func makeNSView(context: Context) -> CustomAnchorNSView {
        let v = CustomAnchorNSView()
        v.onFound = onScrollView
        return v
    }
    func updateNSView(_ nsView: CustomAnchorNSView, context: Context) {
        if let sv = nsView.enclosingScrollView { onScrollView(sv) }
    }
}

final class TimelineScrollCoordinator: ObservableObject {
    static let shared = TimelineScrollCoordinator()
    
    weak var scrollView: NSScrollView?
    @Published var unreadCountAbove: Int = 0
    
    private var preUpdateOriginY: CGFloat = 0.0
    private var preUpdateDocHeight: CGFloat = 0.0
    
    func registerScrollView(_ sv: NSScrollView) {
        self.scrollView = sv
    }
    
    func prepareForPrepend(topTweetId: String?) {
        guard let sv = scrollView else { return }
        preUpdateOriginY = sv.contentView.bounds.origin.y
        preUpdateDocHeight = sv.documentView?.frame.height ?? 0
    }
    
    func adjustAfterPrepend(isUserInitiated: Bool) {
        guard !isUserInitiated else {
            DispatchQueue.main.async {
                self.unreadCountAbove = 0
            }
            return
        }
        guard scrollView != nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let sv = self.scrollView, let docView = sv.documentView else { return }
            let newDocHeight = docView.frame.height
            let addedHeight = newDocHeight - self.preUpdateDocHeight
            
            if addedHeight > 0 {
                // If user was at/near the top (origin.y <= 2.0), AppKit would keep origin at 0.0,
                // which would push the currently viewed tweet downwards.
                // We scroll by addedHeight so that the tweet coordinate remains rock-solid in the user's viewport!
                if self.preUpdateOriginY <= 2.0 {
                    let targetY = self.preUpdateOriginY + addedHeight
                    sv.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                    sv.reflectScrolledClipView(sv.contentView)
                    
                    TrackpadPullCoordinator.shared.isAtTop = false
                    TimelineScrollState.shared.isAtTop = false
                }
            }
        }
    }
    
    func scrollToTop() {
        guard let sv = scrollView else { return }
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sv.contentView.animator().scroll(to: NSPoint(x: 0, y: 0))
            } completionHandler: {
                sv.reflectScrolledClipView(sv.contentView)
                self.unreadCountAbove = 0
                TrackpadPullCoordinator.shared.isAtTop = true
                TimelineScrollState.shared.isAtTop = true
            }
        }
    }
}

// MARK: - Floating New Posts Available Pill
struct NewPostsFloatingPill: View {
    var count: Int
    var onTap: () -> Void
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                Text(loc.format("new_posts_available", ["count": "\(count)"]))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(ThemeManager.accent.opacity(0.92))
                    .shadow(color: Color.black.opacity(theme.isLight ? 0.15 : 0.35), radius: 8, x: 0, y: 4)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .transition(.asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity).combined(with: .move(edge: .top)),
            removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top))
        ))
    }
}

// MARK: - Native Trackpad & ScrollWheel Pull Coordinator
final class TrackpadPullCoordinator {
    static let shared = TrackpadPullCoordinator()
    
    private var eventMonitor: Any?
    private var wheelReleaseTimer: Timer?
    private let threshold: CGFloat = 52.0
    private var activeOwner: String?
    
    var onPullProgress: ((CGFloat) -> Void)?
    var onTriggerRefresh: (() -> Void)?
    var onCancelPull: (() -> Void)?
    
    var isAtTop: Bool = true
    var isRefreshing: Bool = false
    
    // Strict pull activation:
    // Only when a two-finger downward pull begins (.began) while ALREADY at the very top (isAtTop == true && scrollingDeltaY > 0)
    // is a pull-to-refresh session activated.
    // If the scroll began while scrolled down (browsing content upward), isPullGestureActive remains false,
    // so reaching the top during upward browsing will NEVER accidentally trigger pull-to-refresh.
    private var isPullGestureActive: Bool = false
    private var accumulatedPull: CGFloat = 0.0
    private var hasTriggeredHaptic: Bool = false
    
    func startMonitoring(owner: String = "default") {
        activeOwner = owner
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            self.handleScrollEvent(event)
            return event
        }
    }
    
    func stopMonitoring(owner: String = "default") {
        if activeOwner == owner {
            activeOwner = nil
            if let m = eventMonitor {
                NSEvent.removeMonitor(m)
                eventMonitor = nil
            }
            wheelReleaseTimer?.invalidate()
            wheelReleaseTimer = nil
            accumulatedPull = 0
            isPullGestureActive = false
            hasTriggeredHaptic = false
        }
    }
    
    // Progressive Damping Curve (阻尼感递增：从一开始到加载条到loading部分阻力越来越大)
    static func calculateDampedDelta(rawDelta: CGFloat, currentPull: CGFloat, threshold: CGFloat) -> CGFloat {
        if rawDelta < 0 {
            // Releasing/rolling back: responsive and smooth
            return rawDelta * 0.85
        }
        let p = max(0.0, currentPull / threshold)
        // Damping factor:
        // p = 0.0 (start, line extends from left): factor = 0.68
        // p = 0.5 (middle, approaching loading word): factor = 0.43
        // p = 1.0 (loading word cursive drawing): factor = 0.18
        // p > 1.0 (over threshold): heavy resistance factor <= 0.04
        let factor: CGFloat
        if p <= 1.0 {
            factor = 0.68 - 0.50 * (p * p)
        } else {
            factor = max(0.03, 0.18 / (1.0 + (p - 1.0) * 3.5))
        }
        return rawDelta * factor
    }
    
    private func handleScrollEvent(_ event: NSEvent) {
        guard !isRefreshing else { return }
        guard event.window == NSApp.mainWindow || event.window == nil else { return }
        
        let phase = event.phase
        let momentumPhase = event.momentumPhase
        
        // 1. Gesture Began: strictly check if fingers touched while ALREADY at the top with downward swipe
        if phase == .began {
            if isAtTop && event.scrollingDeltaY > 0 {
                isPullGestureActive = true
                accumulatedPull = 0
                hasTriggeredHaptic = false
            } else {
                isPullGestureActive = false
                accumulatedPull = 0
                hasTriggeredHaptic = false
            }
            return
        }
        
        // 2. Gesture Changed: only process if the gesture was initiated at the top
        if phase == .changed {
            if isPullGestureActive && isAtTop {
                let delta = event.scrollingDeltaY
                if delta > 0 || accumulatedPull > 0 {
                    let dampedDelta = Self.calculateDampedDelta(rawDelta: delta, currentPull: accumulatedPull, threshold: threshold)
                    accumulatedPull = max(0, accumulatedPull + dampedDelta)
                    
                    if accumulatedPull >= threshold {
                        if !hasTriggeredHaptic {
                            hasTriggeredHaptic = true
                            NSHapticFeedbackManager.defaultPerformer.perform(
                                .alignment,
                                performanceTime: .now
                            )
                        }
                    } else {
                        if hasTriggeredHaptic {
                            hasTriggeredHaptic = false
                        }
                    }
                    
                    onPullProgress?(accumulatedPull)
                }
            } else if !isAtTop && accumulatedPull > 0 {
                // Moved away from top during pull -> abort immediately
                isPullGestureActive = false
                accumulatedPull = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
                onCancelPull?()
            }
            return
        }
        
        // 3. Gesture Ended: only trigger refresh if this was an active top pull that reached threshold
        if phase == .ended || momentumPhase == .ended {
            if isPullGestureActive {
                isPullGestureActive = false
                if accumulatedPull >= threshold {
                    accumulatedPull = 0
                    hasTriggeredHaptic = false
                    onPullProgress?(0)
                    onTriggerRefresh?()
                } else if accumulatedPull > 0 {
                    // Pull didn't reach the end -> rewind animation, do not execute refresh!
                    accumulatedPull = 0
                    hasTriggeredHaptic = false
                    onPullProgress?(0)
                    onCancelPull?()
                }
            }
            return
        }
        
        // 4. Gesture Cancelled
        if phase == .cancelled || momentumPhase == .cancelled {
            isPullGestureActive = false
            if accumulatedPull > 0 {
                accumulatedPull = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
                onCancelPull?()
            }
            return
        }
        
        // 5. Discrete Notched Mouse Wheel support (when phase is empty)
        if phase.isEmpty && momentumPhase.isEmpty {
            if isAtTop && event.scrollingDeltaY > 0 {
                let delta = event.scrollingDeltaY
                let dampedDelta = Self.calculateDampedDelta(rawDelta: delta * 2.8, currentPull: accumulatedPull, threshold: threshold)
                accumulatedPull = max(0, accumulatedPull + dampedDelta)
                if accumulatedPull >= threshold && !hasTriggeredHaptic {
                    hasTriggeredHaptic = true
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                onPullProgress?(accumulatedPull)
                
                wheelReleaseTimer?.invalidate()
                let timer = Timer(timeInterval: 0.22, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    let didReachThreshold = self.accumulatedPull >= self.threshold
                    self.accumulatedPull = 0
                    self.hasTriggeredHaptic = false
                    self.onPullProgress?(0)
                    if didReachThreshold {
                        self.onTriggerRefresh?()
                    } else {
                        self.onCancelPull?()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.wheelReleaseTimer = timer
            }
        }
    }
}

struct MainTimelineView: View {
    @ObservedObject var viewModel = TimelineViewModel.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var scrollState = TimelineScrollState.shared
    @ObservedObject var scrollCoordinator = TimelineScrollCoordinator.shared
    
    var onOpenSettings: () -> Void
    var onLoginRequest: () -> Void
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            ThemeManager.background
                .ignoresSafeArea()
            
            if !viewModel.isAuthenticated {
                unauthenticatedView
            } else if viewModel.isLoadingInitial && viewModel.tweets.isEmpty {
                skeletonLoadingView
            } else if viewModel.tweets.isEmpty {
                emptyStateView
            } else {
                timelineContent
            }
            
            // Secondary Floating Capsule: Home Feed Filter (For You / Following)
            if viewModel.isAuthenticated {
                HomeFeedCapsuleBar()
                    .padding(.top, nav.sidebarExpanded ? 16 : 62)
                    .zIndex(50)
            }
            
            // Floating New Posts Pill (shown when new posts arrive above the user's current reading position)
            if scrollCoordinator.unreadCountAbove > 0 && viewModel.isAuthenticated {
                NewPostsFloatingPill(count: scrollCoordinator.unreadCountAbove) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.applyPendingTweets(for: viewModel.selectedFeed)
                    }
                    scrollCoordinator.scrollToTop()
                }
                .padding(.top, nav.sidebarExpanded ? 64 : 110)
                .zIndex(55)
            }
            
            // Native Full-Resolution Lightbox Overlay (Smooth Opacity Crossfade)
            ImageLightboxOverlay()
                .animation(.easeInOut(duration: 0.22), value: LightboxManager.shared.isPresented)
        }
        .onAppear {
            TrackpadPullCoordinator.shared.onPullProgress = { distance in
                DispatchQueue.main.async {
                    scrollState.pullDistance = distance
                    scrollState.isPullThresholdExceeded = (distance >= 52.0)
                }
            }
            TrackpadPullCoordinator.shared.onTriggerRefresh = {
                DispatchQueue.main.async {
                    scrollState.isPullThresholdExceeded = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        scrollState.pullDistance = 0
                    }
                    viewModel.refresh(silently: false, isUserInitiated: true)
                }
            }
            TrackpadPullCoordinator.shared.onCancelPull = {
                DispatchQueue.main.async {
                    scrollState.isPullThresholdExceeded = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        scrollState.pullDistance = 0
                    }
                }
            }
            TrackpadPullCoordinator.shared.startMonitoring(owner: "Timeline")
        }
        .onDisappear {
            TrackpadPullCoordinator.shared.stopMonitoring(owner: "Timeline")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MaX_RefreshTimeline"))) { _ in
            if nav.currentTab == .home {
                viewModel.refresh(silently: false, isUserInitiated: true)
            }
        }
    }
    
    // MARK: - Timeline Scroll Content with Pull-to-Refresh
    private var timelineContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Geometry anchor at very top for overscroll tracking
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("timelineScrollViewSpace")).minY
                        )
                    }
                    .frame(height: 0)
                    .id("timelineTopAnchor")
                    
                    // Top subtle spacing under native navigation (capsule vs sidebar)
                    Color.clear
                        .frame(height: nav.sidebarExpanded ? 72 : 118)
                    
                    // Pull-to-Refresh SVG Dynamic Handwriting Indicator Area (Edge-to-Edge)
                    if viewModel.isRefreshing || scrollState.pullDistance > 2 {
                        let pullProg = viewModel.isRefreshing ? 1.0 : min(1.0, scrollState.pullDistance / 52.0)
                        let targetH: CGFloat = viewModel.isRefreshing ? 52 : min(52, max(0, scrollState.pullDistance))
                        let opac: Double = viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, Double(scrollState.pullDistance) / 10.0))
                        
                        SVGRefreshIndicatorView(
                            pullProgress: pullProg,
                            isRefreshing: viewModel.isRefreshing,
                            colorScheme: theme.themeColor
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: targetH)
                        .opacity(opac)
                        .clipped()
                        .transition(.opacity)
                    }
                    
                    // Tweets List
                    ForEach(viewModel.tweets, id: \.id) { tweet in
                        TweetRowView(tweet: tweet)
                            .id(tweet.id)
                    }
                    
                    // Bottom Loading Footer
                    bottomLoadingFooter
                }
                .background(
                    ScrollViewAccessor { sv in
                        TimelineScrollCoordinator.shared.registerScrollView(sv)
                    }
                )
            }
            .coordinateSpace(name: "timelineScrollViewSpace")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                handlePullOffset(offset)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { val in
                        guard !viewModel.isRefreshing, scrollState.isAtTop, val.translation.height > 0 else { return }
                        let rawHeight = val.translation.height
                        let threshold: CGFloat = 52.0
                        let dist: CGFloat
                        if rawHeight <= 60 {
                            dist = rawHeight * 0.62 - (rawHeight * rawHeight) * 0.0025
                        } else {
                            dist = 28.2 + (rawHeight - 60) * 0.22
                        }
                        scrollState.pullDistance = max(0, dist)
                        if dist >= threshold {
                            if !scrollState.hasTriggeredHaptic {
                                scrollState.hasTriggeredHaptic = true
                                NSHapticFeedbackManager.defaultPerformer.perform(
                                    .alignment,
                                    performanceTime: .now
                                )
                            }
                        } else if dist < threshold && scrollState.hasTriggeredHaptic {
                            scrollState.hasTriggeredHaptic = false
                        }
                    }
                    .onEnded { val in
                        guard !viewModel.isRefreshing, scrollState.isAtTop else { return }
                        if scrollState.pullDistance >= 52.0 {
                            scrollState.hasTriggeredHaptic = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                scrollState.pullDistance = 0
                            }
                            viewModel.refresh(silently: false, isUserInitiated: true)
                        } else {
                            scrollState.hasTriggeredHaptic = false
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                scrollState.pullDistance = 0
                            }
                        }
                    }
            )
        }
    }
    
    private func handlePullOffset(_ offset: CGFloat) {
        let isTop = (offset >= -2.0)
        TrackpadPullCoordinator.shared.isAtTop = isTop
        TrackpadPullCoordinator.shared.isRefreshing = viewModel.isRefreshing
        scrollState.isAtTop = isTop
        if isTop {
            TimelineScrollCoordinator.shared.unreadCountAbove = 0
        }
    }
    
    // MARK: - Bottom Loading Footer
    private var bottomLoadingFooter: some View {
        VStack(spacing: 12) {
            if viewModel.isLoadingMore {
                HStack(spacing: 8) {
                    GrowingArcIndicator(color: ThemeManager.accent, lineWidth: 1.5, size: 16)
                    Text(loc.t("loading_more"))
                        .font(.system(size: 13))
                        .foregroundColor(ThemeManager.secondaryText)
                }
                .padding(.vertical, 20)
            } else {
                Color.clear
                    .frame(height: 30)
                    .onAppear {
                        viewModel.loadMore()
                    }
            }
        }
    }
    
    // MARK: - 120Hz Skeleton Loading View
    private var skeletonLoadingView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: nav.sidebarExpanded ? 72 : 118)
                ForEach(0..<6, id: \.self) { _ in
                    TweetSkeletonRow()
                }
            }
        }
    }
    
    // MARK: - Unauthenticated State View
    private var unauthenticatedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(ThemeManager.accent)
            
            Text(loc.t("sign_in_required"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Button(action: onLoginRequest) {
                Text(loc.t("sign_in_button"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(ThemeManager.accent)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Color.clear.frame(height: nav.sidebarExpanded ? 72 : 118)
            Image(systemName: viewModel.selectedFeed.iconName)
                .font(.system(size: 40))
                .foregroundColor(ThemeManager.tertiaryText)
            
            Text(loc.t("empty_timeline"))
                .font(.system(size: 14))
                .foregroundColor(ThemeManager.secondaryText)
            
            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .foregroundColor(ThemeManager.accent)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Secondary Floating Home Feed Capsule Bar (Dual-Mode Liquid Glass)
private struct HomeFeedCapsuleBar: View {
    @ObservedObject var viewModel = TimelineViewModel.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var feedTabNamespace
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(HomeFeedType.allCases) { feed in
                let isSelected = viewModel.selectedFeed == feed
                Button {
                    viewModel.selectFeed(feed)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: feed.iconName)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        
                        Text(loc.t(feed.titleKey))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        
                        if nav.showShortcutBadges {
                            // Shortcut Indicator (⌥Q, ⌥W)
                            Text(feed.shortcutLetter)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            activeFeedBackground
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
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
    private var activeFeedBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : (theme.isLight ? Color.black : Color.white)
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.20))
                    : .regular
                Capsule()
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? (theme.isLight ? 0.14 : 0.22) : (theme.isLight ? 0.08 : 0.14)))
                    .glassEffect(tabGlass, in: Capsule())
                    .matchedGeometryEffect(id: "home-active-feed", in: feedTabNamespace)
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
                    .strokeBorder(ThemeManager.accent.opacity(theme.isLight ? 0.35 : 0.50), lineWidth: 0.8)
            )
            .shadow(color: ThemeManager.accent.opacity(theme.isLight ? 0.15 : 0.25), radius: 6, x: 0, y: 2)
            .matchedGeometryEffect(id: "home-active-feed", in: feedTabNamespace)
    }
}
