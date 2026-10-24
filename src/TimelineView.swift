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
    private var boundsObserver: Any?
    private weak var registeredScrollView: NSScrollView?
    private var wheelReleaseTimer: Timer?
    private let threshold: CGFloat = 65.0
    private var activeOwner: String?
    
    var onPullProgress: ((CGFloat) -> Void)?
    var onTriggerRefresh: (() -> Void)?
    var onCancelPull: (() -> Void)?
    
    var isAtTop: Bool = true
    var isRefreshing: Bool = false
    
    private var currentOverscroll: CGFloat = 0.0
    private var hasTriggeredHaptic: Bool = false
    
    func attachScrollView(_ sv: NSScrollView) {
        if registeredScrollView === sv { return }
        registeredScrollView = sv
        
        sv.verticalScrollElasticity = .allowed
        sv.contentView.postsBoundsChangedNotifications = true
        
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
        
        handleBoundsChanged()
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
            if let obs = boundsObserver {
                NotificationCenter.default.removeObserver(obs)
                boundsObserver = nil
            }
            registeredScrollView = nil
            wheelReleaseTimer?.invalidate()
            wheelReleaseTimer = nil
            currentOverscroll = 0
            hasTriggeredHaptic = false
        }
    }
    
    private func handleBoundsChanged() {
        guard let sv = registeredScrollView else { return }
        let y = sv.contentView.bounds.origin.y
        
        // Exact 0ms top detection: y <= 0.5 means top tweet is at top of viewport
        let atTop = (y <= 0.5)
        self.isAtTop = atTop
        TimelineScrollState.shared.isAtTop = atTop
        if atTop {
            TimelineScrollCoordinator.shared.unreadCountAbove = 0
        }
        
        guard !isRefreshing else { return }
        
        // Native rubber-band overscroll (only physically negative when pulled down beyond the top)
        if y < 0.0 {
            let overscroll = -y
            currentOverscroll = overscroll
            onPullProgress?(overscroll)
            
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
            if currentOverscroll > 0 {
                currentOverscroll = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
            }
        }
    }
    
    private func handleScrollEvent(_ event: NSEvent) {
        guard !isRefreshing else { return }
        guard event.window == NSApp.mainWindow || event.window == nil else { return }
        
        // When touch gesture finishes (user lifts two fingers from trackpad)
        if event.phase == .ended {
            if currentOverscroll >= threshold {
                currentOverscroll = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
                onTriggerRefresh?()
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
                    if self.currentOverscroll >= self.threshold {
                        self.currentOverscroll = 0
                        self.hasTriggeredHaptic = false
                        self.onPullProgress?(0)
                        self.onTriggerRefresh?()
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
                DispatchQueue.main.async {
                    scrollState.pullDistance = distance
                    scrollState.isPullThresholdExceeded = (distance >= 65.0)
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
                    // Top subtle spacing under native navigation (capsule vs sidebar)
                    Color.clear
                        .frame(height: nav.sidebarExpanded ? 36 : 64)
                    
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
                        TrackpadPullCoordinator.shared.attachScrollView(sv)
                    }
                )
            }
            .coordinateSpace(name: "timelineScrollViewSpace")
            .overlay(alignment: .top) {
                if viewModel.isRefreshing || scrollState.pullDistance > 2 {
                    let pullProg = viewModel.isRefreshing ? 1.0 : min(1.0, scrollState.pullDistance / 65.0)
                    let opac: Double = viewModel.isRefreshing ? 1.0 : min(1.0, max(0.0, Double(scrollState.pullDistance) / 10.0))
                    
                    SVGRefreshIndicatorView(
                        pullProgress: pullProg,
                        isRefreshing: viewModel.isRefreshing,
                        colorScheme: theme.themeColor
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .padding(.top, nav.sidebarExpanded ? 36 : 64)
                    .opacity(opac)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
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


