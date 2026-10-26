//
//  TimelineView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI

// MARK: - Scroll Offset Tracker for Pull-to-Refresh
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Live Scroll State
// Kept separate from TimelineScrollState so per-frame pull updates don't re-render the whole timeline.
// While the content is moving (trackpad, momentum, mouse wheel or arrow keys), rows stop hit-testing: otherwise
// SwiftUI re-runs hover hit-testing and AppKit recomputes titlebar drag regions against every row on every frame.
final class TimelineLiveScrollState: ObservableObject {
    static let shared = TimelineLiveScrollState()
    @Published var isLiveScrolling: Bool = false
}

final class TimelineScrollState: ObservableObject {
    static let shared = TimelineScrollState()
    @Published var pullDistance: CGFloat = 0.0
    @Published var isPullThresholdExceeded: Bool = false
    @Published var isAtTop: Bool = true
    var hasTriggeredHaptic: Bool = false
}

extension NSScrollView {
    // Where the content rests at the top. A SwiftUI ScrollView keeps the titlebar safe area inside its document
    // (it rests at -28), while a List's table view rests at 0, so this asks the clip view instead of assuming.
    var restingTopY: CGFloat {
        let bounds = contentView.bounds
        return contentView.constrainBoundsRect(NSRect(x: bounds.minX, y: -100_000, width: bounds.width, height: bounds.height)).minY
    }
}

// MARK: - Native NSScrollView Anchor & Viewport Coordinator
class CustomAnchorNSView: NSView {
    var onFound: ((NSScrollView) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // viewDidMoveToWindow also fires with window == nil when a page is torn down (e.g. on a tab switch), while
        // enclosingScrollView is still set. Reporting it then would re-register the dying page's scroll view over
        // the page that just appeared.
        if window != nil, let sv = enclosingScrollView { onFound?(sv) }
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
        if nsView.window != nil, let sv = nsView.enclosingScrollView { onScrollView(sv) }
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
    
    // MARK: Keyboard Arrow Scrolling (display-synced)
    // A tap glides one step; holding the key scrolls at constant speed until key-up. Driven per frame by the
    // scroll view's display link instead of chained animator() calls, which restart on every key repeat and
    // stall during the system's initial key-repeat delay.
    private let keyStep: CGFloat = 64.0
    private let keyHoldSpeed: CGFloat = 1100.0 // pt/s once the key is held
    private let keyHoldDelay: CFTimeInterval = 0.12
    private var keyDirection: CGFloat = 0
    private var keyIsHeld = false
    private var keyPressTime: CFTimeInterval = 0
    private var keyTargetY: CGFloat = 0
    private var keyCurrentY: CGFloat = 0
    private var keyLastTick: CFTimeInterval = 0
    private var keyDisplayLink: CADisplayLink?
    private var keyUpMonitor: Any?
    
    func arrowKeyDown(up: Bool, isRepeat: Bool) {
        guard let sv = scrollView else { return }
        let direction: CGFloat = up ? -1 : 1
        if isRepeat && keyIsHeld && direction == keyDirection { return }
        
        if keyDisplayLink == nil {
            keyCurrentY = sv.contentView.bounds.origin.y
            keyTargetY = keyCurrentY
        }
        keyDirection = direction
        keyIsHeld = true
        keyPressTime = CACurrentMediaTime()
        keyTargetY = clampedKeyY(keyTargetY + direction * keyStep, in: sv)
        installKeyUpMonitorIfNeeded()
        startKeyDisplayLink(on: sv)
    }
    
    private func installKeyUpMonitorIfNeeded() {
        guard keyUpMonitor == nil else { return }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 125 || event.keyCode == 126 {
                self?.keyIsHeld = false
            }
            return event
        }
        // A key-up delivered to another app never reaches us; stop holding when the window loses focus
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keyIsHeld = false
        }
    }
    
    private func startKeyDisplayLink(on sv: NSScrollView) {
        guard keyDisplayLink == nil else { return }
        keyLastTick = CACurrentMediaTime()
        let link = sv.displayLink(target: self, selector: #selector(keyScrollTick(_:)))
        link.add(to: .main, forMode: .common)
        keyDisplayLink = link
    }
    
    private func stopKeyDisplayLink() {
        keyDisplayLink?.invalidate()
        keyDisplayLink = nil
    }
    
    private func clampedKeyY(_ y: CGFloat, in sv: NSScrollView) -> CGFloat {
        let minY = sv.restingTopY
        let maxY = max(minY, (sv.documentView?.frame.height ?? 0) - sv.contentView.bounds.height)
        return min(maxY, max(minY, y))
    }
    
    @objc private func keyScrollTick(_ link: CADisplayLink) {
        guard let sv = scrollView else { stopKeyDisplayLink(); return }
        let clip = sv.contentView
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 30.0, max(0, now - keyLastTick))
        keyLastTick = now
        
        // The user scrolled by trackpad mid-glide: hand control back to them
        if abs(clip.bounds.origin.y - keyCurrentY) > 1.0 {
            keyCurrentY = clip.bounds.origin.y
            keyTargetY = keyCurrentY
            if !keyIsHeld { stopKeyDisplayLink(); return }
        }
        
        if keyIsHeld && now - keyPressTime >= keyHoldDelay {
            // Advance the target at a fixed rate so held scrolling runs at constant speed
            keyTargetY = clampedKeyY(keyTargetY + keyDirection * keyHoldSpeed * CGFloat(dt), in: sv)
        }
        
        // Exponential approach toward the target: smooth start and a soft stop
        let delta = keyTargetY - keyCurrentY
        if !keyIsHeld && abs(delta) < 0.5 {
            keyCurrentY = keyTargetY
            stopKeyDisplayLink()
        } else {
            keyCurrentY += delta * (1 - exp(-CGFloat(dt) * 16))
        }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: keyCurrentY))
        sv.reflectScrolledClipView(clip)
        keyCurrentY = clip.bounds.origin.y
    }
    
    func scrollToTop() {
        guard let sv = scrollView else { return }
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sv.contentView.animator().scroll(to: NSPoint(x: 0, y: sv.restingTopY))
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
    private var boundsObserver: Any?
    private var lastScrollActivity: CFTimeInterval = 0
    private var scrollIdleTimer: Timer?
    private let scrollIdleDelay: CFTimeInterval = 0.15
    private weak var registeredScrollView: NSScrollView?
    private var wheelReleaseTimer: Timer?
    // Single pull-to-refresh threshold shared by the spinner fill, the haptic and the release trigger
    // (Home and Notifications), so a full ring always means "release to refresh"
    static let refreshThreshold: CGFloat = 38.0
    private let threshold: CGFloat = TrackpadPullCoordinator.refreshThreshold
    private var activeOwner: String?
    // Which page attached the current scroll view. On a tab switch SwiftUI attaches the new page's scroll view
    // before the old page's onDisappear runs, so stopMonitoring must only detach a scroll view its own page attached.
    private var scrollViewOwner: String?

    var onPullProgress: ((CGFloat) -> Void)?
    var onTriggerRefresh: (() -> Void)?
    var onCancelPull: (() -> Void)?
    
    var isAtTop: Bool = true
    var isRefreshing: Bool = false
    
    private var currentOverscroll: CGFloat = 0.0
    private var hasTriggeredHaptic: Bool = false
    // Deepest point of the current pull, and whether this pull has already refreshed
    private var pullPeak: CGFloat = 0
    private var pullTriggered = false
    
    func attachScrollView(_ sv: NSScrollView, owner: String) {
        scrollViewOwner = owner
        if registeredScrollView === sv { return }
        registeredScrollView = sv
        
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        sv.verticalScrollElasticity = .allowed
        sv.contentView.postsBoundsChangedNotifications = true
        
        // 120Hz ProMotion Hardware Acceleration Configurations
        sv.wantsLayer = true
        sv.contentView.wantsLayer = true
        sv.contentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        sv.canDrawConcurrently = true
        
        if let obs = boundsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: sv.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.handleBoundsChanged()
        }

        lastBoundsOriginY = nil
        handleBoundsChanged()
    }
    
    // Any content movement counts as scrolling; it ends after scrollIdleDelay without movement. Bounds changes
    // cover every input (NSScrollView's live-scroll notifications only fire for trackpad gestures).
    private func noteScrollActivity() {
        lastScrollActivity = CACurrentMediaTime()
        if !TimelineLiveScrollState.shared.isLiveScrolling {
            TimelineLiveScrollState.shared.isLiveScrolling = true
        }
        if scrollIdleTimer == nil {
            scheduleScrollIdleCheck(after: scrollIdleDelay)
        }
    }
    
    private func scheduleScrollIdleCheck(after delay: CFTimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.scrollIdleTimer = nil
            let idle = CACurrentMediaTime() - self.lastScrollActivity
            if idle >= self.scrollIdleDelay {
                self.endScrollActivity()
            } else {
                self.scheduleScrollIdleCheck(after: self.scrollIdleDelay - idle)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollIdleTimer = timer
    }
    
    private func endScrollActivity() {
        scrollIdleTimer?.invalidate()
        scrollIdleTimer = nil
        if TimelineLiveScrollState.shared.isLiveScrolling {
            TimelineLiveScrollState.shared.isLiveScrolling = false
        }
    }
    
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
            if scrollViewOwner == owner {
                if let obs = boundsObserver {
                    NotificationCenter.default.removeObserver(obs)
                    boundsObserver = nil
                }
                endScrollActivity()
                registeredScrollView = nil
                scrollViewOwner = nil
            }
            wheelReleaseTimer?.invalidate()
            wheelReleaseTimer = nil
            currentOverscroll = 0
            hasTriggeredHaptic = false
        }
    }
    
    private var lastBoundsOriginY: CGFloat?
    
    private func handleBoundsChanged() {
        guard let sv = registeredScrollView else { return }
        
        let y = sv.contentView.bounds.origin.y
        if let last = lastBoundsOriginY, last != y {
            noteScrollActivity()
        }
        lastBoundsOriginY = y
        let restingTopY = sv.restingTopY
        
        // Exact 0ms top detection: y <= restingTopY + 0.5 means top tweet is at top of viewport
        let atTop = (y <= restingTopY + 0.5)
        if self.isAtTop != atTop {
            self.isAtTop = atTop
            TimelineScrollState.shared.isAtTop = atTop
        }
        if atTop && TimelineScrollCoordinator.shared.unreadCountAbove != 0 {
            TimelineScrollCoordinator.shared.unreadCountAbove = 0
        }
        
        guard !isRefreshing else { return }
        
        // Native rubber-band overscroll (only physically negative when pulled down beyond the resting top)
        if y < (restingTopY - 0.5) {
            let overscroll = restingTopY - y
            currentOverscroll = overscroll
            onPullProgress?(overscroll)
            
            // A List's scroll view tracks the trackpad in its own loop, so the gesture-ended event never reaches
            // the monitor below. Release shows up here instead: past the threshold, the pull starts snapping back.
            pullPeak = max(pullPeak, overscroll)
            if !pullTriggered && pullPeak >= threshold && overscroll <= pullPeak - 6 {
                triggerRefresh()
                return
            }
            
            if overscroll >= threshold {
                if !hasTriggeredHaptic {
                    hasTriggeredHaptic = true
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            } else {
                if hasTriggeredHaptic && overscroll < (threshold - 10.0) {
                    hasTriggeredHaptic = false
                }
            }
        } else {
            pullPeak = 0
            pullTriggered = false
            if currentOverscroll > 0 {
                currentOverscroll = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
            }
        }
    }
    
    private func triggerRefresh() {
        pullTriggered = true
        currentOverscroll = 0
        hasTriggeredHaptic = false
        onPullProgress?(0)
        onTriggerRefresh?()
    }
    
    private func handleScrollEvent(_ event: NSEvent) {
        guard !isRefreshing else { return }
        guard event.window == NSApp.mainWindow || event.window == nil else { return }
        
        // When touch gesture finishes (user lifts two fingers from trackpad)
        if event.phase == .ended {
            if currentOverscroll >= threshold && !pullTriggered {
                triggerRefresh()
            } else if currentOverscroll > 0 {
                currentOverscroll = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
                onCancelPull?()
            }
            return
        }
        
        if event.phase == .cancelled {
            currentOverscroll = 0
            hasTriggeredHaptic = false
            onPullProgress?(0)
            onCancelPull?()
            return
        }
        
        // Discrete notched mouse wheel support (when phase is empty)
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            if currentOverscroll >= threshold {
                wheelReleaseTimer?.invalidate()
                let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    if self.currentOverscroll >= self.threshold && !self.pullTriggered {
                        self.triggerRefresh()
                    } else {
                        self.currentOverscroll = 0
                        self.hasTriggeredHaptic = false
                        self.onPullProgress?(0)
                        self.onCancelPull?()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.wheelReleaseTimer = timer
            }
        }
    }
}

// MARK: - Isolated 120Hz Pull-to-Refresh Indicator Overlay
private struct TimelinePullRefreshIndicatorOverlay: View {
    @ObservedObject var scrollState = TimelineScrollState.shared
    @ObservedObject var viewModel = TimelineViewModel.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var nav = NavigationManager.shared
    
    var body: some View {
        if viewModel.isRefreshing || scrollState.pullDistance > 2.0 {
            let baseTop: CGFloat = nav.sidebarExpanded ? 36 : 64
            let pullDist = viewModel.isRefreshing ? 40.0 : scrollState.pullDistance
            let pullProg: CGFloat = viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, pullDist / TrackpadPullCoordinator.refreshThreshold))
            let opac: Double = viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, Double(pullDist - 2.0) / 8.0))
            
            // Pure GPU translation offset to avoid subpixel frame resizing passes
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

struct MainTimelineView: View {
    @ObservedObject var viewModel = TimelineViewModel.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var scrollCoordinator = TimelineScrollCoordinator.shared
    @ObservedObject var listMetrics = ListMetrics.shared

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
            
            // Floating New Posts Pill (shown when new posts arrive above the user's current reading position)
            if scrollCoordinator.unreadCountAbove > 0 && viewModel.isAuthenticated {
                NewPostsFloatingPill(count: scrollCoordinator.unreadCountAbove) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.applyPendingTweets(for: viewModel.selectedFeed)
                    }
                    scrollCoordinator.scrollToTop()
                }
                .padding(.top, nav.sidebarExpanded ? 16 : 60)
                .zIndex(55)
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
                viewModel.refresh(silently: false, isUserInitiated: true)
            }
            TrackpadPullCoordinator.shared.onCancelPull = {
                TimelineScrollState.shared.isPullThresholdExceeded = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    TimelineScrollState.shared.pullDistance = 0
                }
            }
            TrackpadPullCoordinator.shared.startMonitoring(owner: "Timeline")
        }
        .onDisappear {
            TrackpadPullCoordinator.shared.stopMonitoring(owner: "Timeline")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Tweetintosh_RefreshTimeline"))) { _ in
            if nav.currentTab == .home && !nav.hasOverlay {
                viewModel.reloadFromShortcut()
            }
        }
    }
    
    // MARK: - Timeline Scroll Content with Pull-to-Refresh
    // The timeline is a SwiftUI List (backed by NSTableView on macOS)
    private var timelineContent: some View {
        List {
            // The list's scroll view has no titlebar inset (unlike ScrollView), so the titlebar height is added here
            Color.clear
                .frame(height: (nav.sidebarExpanded ? 36 : 64) + (viewModel.isRefreshing ? 40 : 0) + listMetrics.titlebarInset)
                .background(
                    ScrollViewAccessor { sv in
                        TimelineScrollCoordinator.shared.registerScrollView(sv)
                        TrackpadPullCoordinator.shared.attachScrollView(sv, owner: "Timeline")
                        ListLoadMoreWatcher.shared.attach(sv) { viewModel.loadMore() }
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            
            ForEach(viewModel.tweets, id: \.id) { tweet in
                TweetRowView(tweet: tweet)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            
            GrowingArcIndicator(color: ThemeManager.accent, lineWidth: 1.5, size: 16)
                .opacity(viewModel.isLoadingMore ? 1 : 0)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
.environment(\.peekScope, .timeline)
        .overlay(alignment: .top) {
            TimelinePullRefreshIndicatorOverlay()
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

// MARK: - List Prototype Support

import os

// Loads the next page when the reader gets within 1.5 screens of the bottom, read straight from the scroll view
// instead of a footer row's onAppear (List recycles rows, so that callback is unreliable)
final class ListLoadMoreWatcher {
    static let shared = ListLoadMoreWatcher()
    
    private weak var scrollView: NSScrollView?
    private var observer: Any?
    private var onLoadMore: (() -> Void)?
    
    func attach(_ sv: NSScrollView, onLoadMore: @escaping () -> Void) {
        self.onLoadMore = onLoadMore
        ListMetrics.shared.update(from: sv.window)
        guard scrollView !== sv else { return }
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        scrollView = sv
        sv.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main
        ) { [weak self] _ in
            self?.check()
        }
    }
    
    private func check() {
        guard let sv = scrollView, let doc = sv.documentView else { return }
        let clip = sv.contentView.bounds
        if doc.frame.height - clip.maxY < clip.height * 1.5 {
            onLoadMore?()
        }
    }
}
