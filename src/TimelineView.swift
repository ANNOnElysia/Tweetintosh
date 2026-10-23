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
        
        // Trackpad scroll gesture with phase
        if isAtTop {
            if event.phase == .began || event.phase == .changed {
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
            } else if event.phase == .ended || event.momentumPhase == .ended {
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
            } else if event.phase == .cancelled || event.momentumPhase == .cancelled {
                accumulatedPull = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
                onCancelPull?()
            } else if event.phase.isEmpty {
                // Notched mouse wheel support
                let delta = event.scrollingDeltaY
                if delta > 0 || accumulatedPull > 0 {
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
        } else {
            if accumulatedPull > 0 {
                accumulatedPull = 0
                hasTriggeredHaptic = false
                onPullProgress?(0)
                onCancelPull?()
            }
        }
    }
}

struct MainTimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var scrollState = TimelineScrollState.shared
    
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
            
            // Native Full-Resolution Lightbox Overlay
            ImageLightboxOverlay()
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
                    viewModel.refresh(silently: false)
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
            viewModel.refresh(silently: false)
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
                        .frame(height: nav.sidebarExpanded ? 36 : 62)
                    
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
                        // Progressive damping for mouse drag:
                        // Starts light and responsive, becomes progressively stiffer towards 52pt
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
                            viewModel.refresh(silently: false)
                        } else {
                            // Cancelled before reaching bottom -> smooth rewind animation!
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
        let isTop = (offset >= -16.0)
        TrackpadPullCoordinator.shared.isAtTop = isTop
        TrackpadPullCoordinator.shared.isRefreshing = viewModel.isRefreshing
        scrollState.isAtTop = isTop
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
                Color.clear.frame(height: 44)
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
            Image(systemName: "bubble.left.and.bubble.right")
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
