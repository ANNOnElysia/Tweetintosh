//
//  NotificationsView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit

struct NotificationsView: View {
    @ObservedObject var viewModel = NotificationsViewModel.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @StateObject private var scrollState = TimelineScrollState()
    
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
            NotificationFilterCapsuleBar()
                .padding(.top, nav.sidebarExpanded ? 16 : 62)
                .zIndex(50)
        }
        .onAppear {
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
            TrackpadPullCoordinator.shared.startMonitoring()
        }
        .onDisappear {
            TrackpadPullCoordinator.shared.stopMonitoring()
        }
    }
    
    // MARK: - Notifications Scroll Content
    private var notificationsContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Top Geometry anchor for pull offset tracking
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("notifScrollViewSpace")).minY
                        )
                    }
                    .frame(height: 0)
                    .id("notifTopAnchor")
                    
                    // Clearance under top capsules (Primary Capsule + Secondary Filter Capsule)
                    Color.clear
                        .frame(height: nav.sidebarExpanded ? 72 : 118)
                    
                    // Pull-to-Refresh Indicator
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
                    
                    // Items List or Empty Placeholder
                    if viewModel.filteredItems.isEmpty {
                        emptyFilterView
                    } else {
                        ForEach(viewModel.filteredItems) { item in
                            NotificationRowView(item: item)
                                .id(item.id)
                            
                            // Subtle divider separating notification items (matching Home)
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 0.5)
                        }
                    }
                    
                    // Bottom Spacer
                    Color.clear
                        .frame(height: 40)
                }
            }
            .coordinateSpace(name: "notifScrollViewSpace")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                let isTop = (offset >= -16.0)
                TrackpadPullCoordinator.shared.isAtTop = isTop
                TrackpadPullCoordinator.shared.isRefreshing = viewModel.isRefreshing
                scrollState.isAtTop = isTop
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { val in
                        guard !viewModel.isRefreshing, scrollState.isAtTop, val.translation.height > 0 else { return }
                        let rawHeight = val.translation.height
                        let dist = rawHeight <= 60 ? rawHeight * 0.62 - (rawHeight * rawHeight) * 0.0025 : 28.2 + (rawHeight - 60) * 0.22
                        scrollState.pullDistance = max(0, dist)
                    }
                    .onEnded { val in
                        guard !viewModel.isRefreshing, scrollState.isAtTop else { return }
                        if scrollState.pullDistance >= 52.0 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                scrollState.pullDistance = 0
                            }
                            viewModel.refresh(silently: false)
                        } else {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                scrollState.pullDistance = 0
                            }
                        }
                    }
            )
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
                    HStack(spacing: 5) {
                        Image(systemName: filter.iconName)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        
                        Text(loc.t(filter.titleKey))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        
                        // Shortcut Indicator (⌥Q, ⌥W, ⌥E, ⌥R)
                        Text(filter.shortcutKey)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(isSelected ? ThemeManager.accent.opacity(0.85) : Color.white.opacity(0.35))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(isSelected ? ThemeManager.accent.opacity(0.16) : Color.white.opacity(0.06))
                            )
                    }
                    .foregroundColor(isSelected ? ThemeManager.accent : Color.white.opacity(0.70))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            activeFilterBackground
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
        .fixedSize()
    }
    
    @ViewBuilder
    private var activeFilterBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : Color.white
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(0.20))
                    : .regular
                Capsule()
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? 0.22 : 0.14))
                    .glassEffect(tabGlass, in: Capsule())
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
            .fill(ThemeManager.accent.opacity(0.26))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.7)
                    .allowsHitTesting(false)
            )
            .matchedGeometryEffect(id: "notif-active-filter", in: filterTabNamespace)
    }
}

// MARK: - Individual Notification Row View
private struct NotificationRowView: View {
    var item: NotificationItem
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: Type Icon Badge (Heart, Retweet, Reply, Mention)
            ZStack {
                Circle()
                    .fill(item.type.accentColor.opacity(0.18))
                    .frame(width: 32, height: 32)
                
                Image(systemName: item.type.iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(item.type.accentColor)
            }
            .padding(.top, 2)
            
            // Center & Right Content
            VStack(alignment: .leading, spacing: 6) {
                // Actor Avatar(s) & Timestamp
                HStack(alignment: .center, spacing: 8) {
                    // Small circular user avatar icon
                    Circle()
                        .fill(Color(white: 0.16))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.7))
                        )
                    
                    // Summary text (e.g. "Lumine and Amber liked your post")
                    Text(item.actionSummary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.92))
                    
                    Spacer()
                    
                    // Relative Time
                    Text(item.relativeTime)
                        .font(.system(size: 12))
                        .foregroundColor(ThemeManager.tertiaryText)
                }
                
                // Reply/Comment body if applicable
                if let reply = item.replyBody {
                    Text(reply)
                        .font(theme.tweetFont(size: 13.5))
                        .foregroundColor(Color.white.opacity(0.85))
                        .padding(.vertical, 2)
                }
                
                // Quoted/Target Tweet Excerpt Card
                if let targetSnippet = item.targetTweetSnippet {
                    Text(targetSnippet)
                        .font(theme.tweetFont(size: 12.5))
                        .foregroundColor(Color.white.opacity(0.60))
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                                )
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
