//
//  AppRootView.swift
//  Tweetintosh - Liquid Glass adaptive navigation shell
//

import SwiftUI
import AppKit

// MARK: - Native AppKit Visual Effect View (True macOS Translucent Gaussian Blur)
final class NonInteractiveVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Transparent to all mouse clicks so SwiftUI buttons receive events immediately
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NonInteractiveVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Adaptive Glass Modifier (Liquid Glass Mode vs Frosted Glass Off Mode)
struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    var isLiquid: Bool
    var shape: S
    // Clear variant: .clear glass with a light backing fill, so content behind stays visible (top tab switcher)
    var isClear: Bool = false
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        if isLiquid {
            if #available(macOS 26.0, *) {
                // Mode A: Native Liquid Glass (SwiftUI macOS 26+ native API)
                let base: Glass = isClear ? .clear : .regular
                let glassStyle: Glass = theme.useLiquidGlassTint
                    ? base.tint(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.16)).interactive()
                    : base.interactive()
                let backingFill: Color = isClear
                    ? (theme.isLight ? Color.white.opacity(0.22) : Color.black.opacity(0.10))
                    : (theme.isLight ? Color.white.opacity(0.68) : Color.black.opacity(0.20))

                content
                    .background(
                        shape.fill(backingFill)
                    )
                    .glassEffect(glassStyle, in: shape)
                    .overlay(
                        shape.stroke(
                            theme.isLight ? Color(hex: "#DED9CB").opacity(0.85) : Color.white.opacity(0.20),
                            lineWidth: 0.75
                        )
                        .allowsHitTesting(false)
                    )
                    .shadow(
                        color: Color.black.opacity(theme.isLight ? 0.08 : 0.35),
                        radius: theme.isLight ? 10 : 14,
                        x: 0,
                        y: theme.isLight ? 3 : 5
                    )
            } else {
                fallbackFrostedGlass(content: content)
            }
        } else {
            // Mode B: Liquid Glass Disabled - Pure High-grade Gaussian Blur (VisualEffectView)
            fallbackFrostedGlass(content: content)
        }
    }
    
    @ViewBuilder
    private func fallbackFrostedGlass(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBackground(
                        material: theme.isLight ? .headerView : .sidebar,
                        blendingMode: .withinWindow
                    )
                    (theme.isLight ? Color.white.opacity(0.72) : Color(white: 0.08).opacity(0.42))
                }
                .clipShape(shape)
            )
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: theme.isLight ? [
                                Color(hex: "#DED9CB").opacity(0.85),
                                Color(hex: "#ECE8DC").opacity(0.60),
                                Color.white.opacity(0.90)
                            ] : [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: Color.black.opacity(theme.isLight ? 0.08 : 0.35),
                radius: theme.isLight ? 10 : 14,
                x: 0,
                y: theme.isLight ? 3 : 5
            )
    }
}

// MARK: - AppRootView (Adaptive Shell)
struct AppRootView: View {
    @ObservedObject private var nav = NavigationManager.shared
    var onOpenSettings: () -> Void = {}
    var onLoginRequest: () -> Void = {}

    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()
            
            // Content Layout: Floating Sidebar Droplet (when expanded) + Destination View
            HStack(spacing: 0) {
                if nav.sidebarExpanded {
                    LiquidGlassSidebar(
                        selection: $nav.currentTab,
                        isExpanded: $nav.sidebarExpanded,
                        onOpenSettings: onOpenSettings
                    )
                    .frame(width: 216)
                    .padding(.leading, 12)
                    .padding(.top, 42) // Leaves clean space for macOS traffic lights above
                    .padding(.bottom, 12)
                    .padding(.trailing, 6)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                            removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.94))
                        )
                    )
                }
                
                destination
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Top Floating Capsule Bar (Horizontal Droplet)
            // Visible when sidebar is collapsed and not viewing tweet detail.
            // Leftmost button clicks to wake sidebar and capsule disappears.
            // Sidebar close button clicks to hide sidebar and capsule "卷土重来".
            if !nav.sidebarExpanded && !nav.hasOverlay {
                LiquidGlassCapsule(
                    selection: $nav.currentTab,
                    onToggleSidebar: {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            nav.sidebarExpanded = true
                        }
                    }
                )
                .padding(.top, 14)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: -8)),
                        removal: .scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: -8))
                    )
                )
                .zIndex(100)
            }
            
            // Suggestions under the search field (typeahead, or recent searches when it is empty)
            if nav.isSearchActive && !nav.sidebarExpanded && !nav.hasOverlay {
                SearchSuggestionsPanel()
                    .padding(.top, 66)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .zIndex(101)
            }
            
            // Full-pane pages (tweet detail, profiles), stacked newest on top
            ForEach(Array(nav.overlayStack.enumerated()), id: \.element.id) { index, entry in
                Group {
                    switch entry.page {
                    case .tweet(let tweet):
                        TweetDetailView(tweet: tweet) {
                            nav.dismissTweetDetail()
                        }
                    case .profile(let user):
                        ProfileView(user: user) {
                            nav.dismissTweetDetail()
                        }
                    case .search(let query):
                        SearchView(query: query) {
                            nav.dismissTweetDetail()
                        }
                    case .article(let tweet):
                        ArticleReaderView(tweet: tweet) {
                            nav.dismissTweetDetail()
                        }
                    case .users(let kind, let tweetId):
                        UserListView(kind: kind, tweetId: tweetId) {
                            nav.dismissTweetDetail()
                        }
                    }
                }
                .environment(\.peekScope, .overlay(index))
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
                .zIndex(900 + Double(index))
            }
            
            // Full-Window Lightbox Overlay (covers entire window including top bar)
            ImageLightboxOverlay()
                .ignoresSafeArea()
                .zIndex(999)
            
            // Full-Window Video Lightbox Overlay (native AVPlayer + subtitles + quality control)
            VideoLightboxOverlay()
                .zIndex(1000)
            
            // Deep-press peek card (media, links, profiles)
            PeekOverlay()
                .zIndex(9000)
            
            // Global App Toast Overlay (Action Feedback: Copy, Save, Retweet)
            AppToastOverlay()
                .zIndex(9999)
        }
        .background(AppWindowOrigin.Anchor())
        .coordinateSpace(name: "AppWindow")
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: nav.sidebarExpanded)
        .sheet(isPresented: $nav.isShowingCompose) {
            TweetComposerSheet(quotedTweet: nav.composeQuotedTweet)
        }
        .sheet(item: $nav.replyTargetTweet) { tweet in
            ReplyComposerSheet(tweet: tweet)
        }
    }

    @ViewBuilder private var destination: some View {
        switch nav.currentTab {
        case .home:
            NavigationStack {
                MainTimelineView(onOpenSettings: onOpenSettings, onLoginRequest: onLoginRequest)
            }
        case .notifications:
            NavigationStack {
                NotificationsView(onOpenSettings: onOpenSettings, onLoginRequest: onLoginRequest)
            }
        case .messages:
            NavigationStack {
                NewDestinationPlaceholderView(title: "Messages", icon: "bubble.left.and.bubble.right.fill")
            }
        }
    }
}

// MARK: - Top Floating Capsule (Horizontal Droplet)
private struct LiquidGlassCapsule: View {
    @Binding var selection: AppTab
    var onToggleSidebar: () -> Void
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var capsuleTabNamespace
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. Leftmost: Sidebar Toggle Button [|]
            Button(action: onToggleSidebar) {
                HStack(spacing: 3) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText.opacity(0.85) : Color.white.opacity(0.88))
                    
                    if nav.showShortcutBadges {
                        Text("⌥`")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.85))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, nav.showShortcutBadges ? 8 : 8)
                .background(
                    Capsule()
                        .fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 6)
            .help("Toggle Sidebar (⌥`)")
            
            // Subtle vertical divider
            Rectangle()
                .fill(theme.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.18))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 6)
            
            // 2. Center Content: Either the 3 Tabs OR the Inline Liquid Glass Search Field
            ZStack {
                if !nav.isSearchActive {
                    // Center Tabs: Home, Notifications, Messages (Dynamic Width, No Truncation)
                    HStack(spacing: 3) {
                        ForEach(AppTab.allCases) { tab in
                            let isSelected = selection == tab && !nav.isSearchActive
                            Button {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    selection = tab
                                    nav.isSearchActive = false
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.iconName)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    Text(tabTitle(tab))
                                        .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .layoutPriority(1)
                                    
                                    if nav.showShortcutBadges {
                                        Text(tabShortcut(tab))
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
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(isSelected ? 2 : 1)
                                .background {
                                    if isSelected {
                                        activeTabBackground
                                    }
                                }
                                .contentShape(Capsule())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .transition(.opacity)
                } else {
                    // Inline Liquid Glass Search Input Field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ThemeManager.accent)
                            .padding(.leading, 10)
                        
                        TextField(loc.t("search_placeholder"), text: $nav.searchQuery)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 12.5))
                            .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                            .focused($isSearchFocused)
                            .onSubmit {
                                // Return opens the highlighted suggestion, or searches for the typed text;
                                // the field closes behind it
                                SearchSuggestionsModel.shared.submit(typed: nav.searchQuery)
                            }
                            .onChange(of: nav.searchQuery) { _, text in
                                SearchSuggestionsModel.shared.update(query: text)
                            }
                            .onKeyPress(.downArrow) {
                                SearchSuggestionsModel.shared.move(1)
                                return .handled
                            }
                            .onKeyPress(.upArrow) {
                                SearchSuggestionsModel.shared.move(-1)
                                return .handled
                            }
                            .onExitCommand {
                                nav.toggleSearch()
                            }
                        
                        if !nav.searchQuery.isEmpty {
                            Button {
                                nav.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.trailing, 8)
                        } else {
                            Text("esc")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(theme.isLight ? ThemeManager.tertiaryText : Color.white.opacity(0.40))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08))
                                )
                                .padding(.trailing, 8)
                        }
                    }
                    .frame(width: 280, height: 30)
                    .background(innerSearchGlassBackground)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: nav.isSearchActive)
            .onChange(of: nav.isSearchActive) { _, active in
                if active {
                    SearchSuggestionsModel.shared.update(query: nav.searchQuery)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        isSearchFocused = true
                    }
                } else {
                    isSearchFocused = false
                    SearchSuggestionsModel.shared.reset()
                }
            }
            
            // Subtle vertical divider
            Rectangle()
                .fill(theme.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.18))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 6)
            
            // 3. Rightmost: Search Magnifying Glass / Close Button
            Button(action: {
                nav.toggleSearch()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: nav.isSearchActive ? "xmark" : "magnifyingglass")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(nav.isSearchActive ? ThemeManager.accent : (theme.isLight ? ThemeManager.primaryText.opacity(0.85) : Color.white.opacity(0.85)))
                    
                    if nav.showShortcutBadges {
                        Text("⌥S")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(nav.isSearchActive ? ThemeManager.accent : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.85)))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(nav.isSearchActive ? ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.16) : (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12)))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, nav.showShortcutBadges ? 8 : 8)
                .background {
                    if nav.isSearchActive {
                        Capsule().fill(theme.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.20))
                    } else {
                        Capsule().fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 6)
            .help(nav.isSearchActive ? "Close Search (Esc / ⌥S)" : "Search (⌥S)")
        }
        .padding(.vertical, 4)
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule(), isClear: true))
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: nav.showShortcutBadges)
        .fixedSize()
    }
    
    @ViewBuilder
    private var innerSearchGlassBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let glassStyle: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.18))
                    : .regular
                Capsule()
                    .fill(
                        theme.useLiquidGlassTint
                            ? ThemeManager.accent.opacity(theme.isLight ? 0.10 : 0.12)
                            : (theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                    )
                    .glassEffect(glassStyle, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: theme.isLight ? [
                                        Color.black.opacity(0.14),
                                        Color.black.opacity(0.06)
                                    ] : [
                                        Color.white.opacity(0.32),
                                        Color.white.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                            .allowsHitTesting(false)
                    )
            } else {
                fallbackSearchBackground
            }
        } else {
            fallbackSearchBackground
        }
    }
    
    private var fallbackSearchBackground: some View {
        Capsule()
            .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.09))
            .overlay(
                Capsule()
                    .strokeBorder(theme.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.18), lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
    }
    
    @ViewBuilder
    private var activeTabBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : (theme.isLight ? Color.black : Color.white)
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.20))
                    : .regular
                Capsule()
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? (theme.isLight ? 0.14 : 0.24) : (theme.isLight ? 0.08 : 0.16)))
                    .glassEffect(tabGlass, in: Capsule())
                    .matchedGeometryEffect(id: "capsule-active-tab", in: capsuleTabNamespace)
            } else {
                defaultActiveTabBackground
            }
        } else {
            defaultActiveTabBackground
        }
    }
    
    private var defaultActiveTabBackground: some View {
        Capsule()
            .fill(theme.isLight ? ThemeManager.accent.opacity(0.18) : ThemeManager.accent.opacity(0.28))
            .overlay(
                Capsule()
                    .stroke(theme.isLight ? ThemeManager.accent.opacity(0.35) : Color.white.opacity(0.25), lineWidth: 0.7)
                    .allowsHitTesting(false)
            )
            .matchedGeometryEffect(id: "capsule-active-tab", in: capsuleTabNamespace)
    }
    
    private func tabTitle(_ tab: AppTab) -> String {
        switch tab {
        case .home:
            let t = loc.t("tab_home")
            return t.isEmpty ? "Home" : t
        case .notifications:
            let t = loc.t("tab_notifications")
            return t.isEmpty ? "Notifications" : t
        case .messages:
            let t = loc.t("tab_messages")
            return t.isEmpty ? "Messages" : t
        }
    }
    
    private func tabShortcut(_ tab: AppTab) -> String {
        switch tab {
        case .home: return "⌥1"
        case .notifications: return "⌥2"
        case .messages: return "⌥3"
        }
    }
}

// MARK: - Floating Vertical Sidebar Droplet (Dual-Mode: Floating Liquid Glass vs Frosted Glass)
private struct LiquidGlassSidebar: View {
    @Binding var selection: AppTab
    @Binding var isExpanded: Bool
    var onOpenSettings: () -> Void
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var selectionNamespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: App Logo + Sidebar Close Button
            HStack(alignment: .center) {
                Text("Tweetintosh")
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                
                Spacer()
                
                // Sidebar Close Button (dismisses sidebar and brings capsule back)
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        isExpanded = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(ThemeManager.accent)
                        
                        if nav.showShortcutBadges {
                            Text("⌥`")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(ThemeManager.accent.opacity(0.85))
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.15))
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .frame(height: 28)
                    .padding(.horizontal, nav.showShortcutBadges ? 6 : 6)
                    .background(
                        Capsule()
                            .fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle Sidebar (⌥`)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
            
            // Navigation Tabs
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13.5, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? ThemeManager.accent : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.65)))
                            .frame(width: 20)
                        
                        Text(tabTitle(tab))
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? ThemeManager.accent : (theme.isLight ? ThemeManager.primaryText.opacity(0.80) : Color.white.opacity(0.75)))
                        
                        Spacer()
                        
                        if nav.showShortcutBadges {
                            Text(tabShortcut(tab))
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? ThemeManager.accent.opacity(0.9) : (theme.isLight ? ThemeManager.tertiaryText : Color.white.opacity(0.40)))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(isSelected ? ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.16) : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06)))
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            sidebarActiveTabBackground
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                
                // Filters under Notifications (All / Likes & Reposts / Comments / Mentions)
                if tab == .notifications {
                    SidebarNotificationFilterSection()
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }
                
                // Parallel Feed Selector under Home (推荐 / 关注中 / 列表)
                if tab == .home {
                    SidebarHomeFeedSection(selection: $selection)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }
            }
            
            Spacer()
            
            // New Post Button
            Button(action: {
                nav.openComposer()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ThemeManager.onAccent)
                        .frame(width: 20)
                    Text(loc.t("new_post"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ThemeManager.onAccent)
                    
                    Spacer()
                    
                    if nav.showShortcutBadges {
                        Text("↩↩")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(Color.white.opacity(0.25))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ThemeManager.accent)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            
            // Bottom Settings Button
            Button(action: onOpenSettings) {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5))
                        .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.60))
                        .frame(width: 20)
                    Text(loc.t("settings"))
                        .font(.system(size: 12.5))
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText.opacity(0.85) : Color.white.opacity(0.70))
                    
                    Spacer()
                    
                    if nav.showShortcutBadges {
                        Text("⌘,")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.isLight ? ThemeManager.tertiaryText : Color.white.opacity(0.40))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.04))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .modifier(
            AdaptiveGlassModifier(
                isLiquid: theme.useLiquidGlass,
                shape: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: nav.showShortcutBadges)
    }
    
    private func tabTitle(_ tab: AppTab) -> String {
        switch tab {
        case .home:
            let t = loc.t("tab_home")
            return t.isEmpty ? "Home" : t
        case .notifications:
            let t = loc.t("tab_notifications")
            return t.isEmpty ? "Notifications" : t
        case .messages:
            let t = loc.t("tab_messages")
            return t.isEmpty ? "Messages" : t
        }
    }
    
    private func tabShortcut(_ tab: AppTab) -> String {
        switch tab {
        case .home: return "⌥1"
        case .notifications: return "⌥2"
        case .messages: return "⌥3"
        }
    }
    
    @ViewBuilder
    private var sidebarActiveTabBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : (theme.isLight ? Color.black : Color.white)
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.22))
                    : .regular
                Capsule(style: .continuous)
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? (theme.isLight ? 0.14 : 0.20) : (theme.isLight ? 0.08 : 0.14)))
                    .glassEffect(tabGlass, in: Capsule(style: .continuous))
                    .matchedGeometryEffect(id: "sidebar-active-tab", in: selectionNamespace)
            } else {
                defaultSidebarActiveTabBackground
            }
        } else {
            defaultSidebarActiveTabBackground
        }
    }
    
    private var defaultSidebarActiveTabBackground: some View {
        Capsule(style: .continuous)
            .fill(theme.isLight ? ThemeManager.accent.opacity(0.16) : ThemeManager.accent.opacity(0.22))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(theme.isLight ? ThemeManager.accent.opacity(0.35) : Color.white.opacity(0.18), lineWidth: 0.6)
                    .allowsHitTesting(false)
            )
            .matchedGeometryEffect(id: "sidebar-active-tab", in: selectionNamespace)
    }
}

// MARK: - Sidebar Notification Filters (the same filters as the floating bar, shown under Notifications)
private struct SidebarNotificationFilterSection: View {
    @ObservedObject var viewModel = NotificationsViewModel.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var filterNamespace
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotificationFilter.allCases) { filter in
                let isSelected = viewModel.selectedFilter == filter
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        if nav.currentTab != .notifications { nav.currentTab = .notifications }
                        viewModel.selectFilter(filter)
                    }
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: filter.iconName)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        if nav.showShortcutBadges {
                            Text(filter.shortcutKey)
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .opacity(0.8)
                        }
                    }
                    .foregroundColor(isSelected ? ThemeManager.accent : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.65)))
                    .frame(maxWidth: .infinity)
                    .frame(height: nav.showShortcutBadges ? 34 : 28)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(theme.isLight ? ThemeManager.accent.opacity(0.16) : ThemeManager.accent.opacity(0.24))
                                .overlay(Capsule(style: .continuous).stroke(ThemeManager.accent.opacity(theme.isLight ? 0.35 : 0.45), lineWidth: 0.6))
                                .matchedGeometryEffect(id: "sidebar-notif-filter", in: filterNamespace)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
                .help(loc.t(filter.titleKey))
            }
        }
        .padding(2.5)
        .background(
            Capsule(style: .continuous)
                .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.6)
                )
        )
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: nav.showShortcutBadges)
    }
}

// MARK: - Sidebar Home Feed Section (Parallel Feeds under Home: 推荐, 关注中, 列表)
private struct SidebarHomeFeedSection: View {
    @Binding var selection: AppTab
    @ObservedObject var timelineVM = TimelineViewModel.shared
    @ObservedObject var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var feedNamespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // First row: For You and Following. Second row: Lists (with its dropdown), only if the user has lists.
            HStack(spacing: 2) {
                // 1. 推荐 (For You)
                feedButton(type: .forYou)
                
                // 2. 关注中 (Following)
                feedButton(type: .following)
            }
            .padding(2.5)
            .background(feedRowBackground)
            
            if !timelineVM.userLists.isEmpty {
                HStack(spacing: 2) {
                    // 3. 列表 (List with dropdown menu)
                    listFeedButton
                }
                .padding(2.5)
                .background(feedRowBackground)
            }
            
            // If List is currently selected and user has lists, show active list banner
            if timelineVM.selectedFeed == .list && !timelineVM.userLists.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: timelineVM.selectedList?.iconName ?? "list.bullet")
                        .font(.system(size: 10.5))
                        .foregroundColor(ThemeManager.accent)
                    
                    Text(timelineVM.selectedList?.name ?? loc.t("feed_list"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText.opacity(0.9) : Color.white.opacity(0.88))
                        .lineLimit(1)
                    
                    if let count = timelineVM.selectedList?.memberCount, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.65))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                            )
                    }
                    
                    Spacer()
                    
                    listPickerMenu
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(ThemeManager.accent.opacity(theme.isLight ? 0.09 : 0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(ThemeManager.accent.opacity(theme.isLight ? 0.25 : 0.35), lineWidth: 0.6)
                        )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
    
    // The rounded track behind each row of feed buttons
    private var feedRowBackground: some View {
        Capsule(style: .continuous)
            .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08), lineWidth: 0.6)
            )
    }
    
    // Regular feed button (For You / Following)
    private func feedButton(type: HomeFeedType) -> some View {
        let isSelected = (selection == .home && timelineVM.selectedFeed == type)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                selection = .home
                timelineVM.selectFeed(type)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .frame(width: 20)
                
                Text(loc.t(type.titleKey))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                if nav.showShortcutBadges {
                    Text(type.shortcutLetter)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? ThemeManager.accent : ThemeManager.tertiaryText)
                        .padding(.horizontal, 2.5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSelected ? ThemeManager.accent.opacity(0.15) : Color.black.opacity(0.05))
                        )
                }
            }
            .foregroundColor(isSelected ? ThemeManager.accent : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.65)))
            .padding(.leading, 8.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 28)
            .background {
                if isSelected {
                    feedActiveBackground
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // List feed button with dropdown menu: a plain row that pops up a native menu (a SwiftUI Menu draws its own label
    // and would not line its icon up with the other rows)
    private var listFeedButton: some View {
        let isSelected = (selection == .home && timelineVM.selectedFeed == .list)
        return Button(action: showListMenu) {
            listRowVisual(isSelected: isSelected)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func showListMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: loc.t("select_list"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for list in timelineVM.userLists {
            let title = list.name + (list.memberCount > 0 ? " · \(list.memberCount)" : "")
            menu.addItem(ClosureMenuItem(
                title: title, symbol: list.iconName,
                isChecked: timelineVM.selectedFeed == .list && timelineVM.selectedListId == list.id
            ) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    selection = .home
                    timelineVM.selectList(list)
                }
            })
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(ClosureMenuItem(title: loc.t("refresh_lists"), symbol: "arrow.clockwise") {
            timelineVM.fetchUserLists()
        })
        menu.addItem(ClosureMenuItem(title: loc.t("manage_lists_on_x"), symbol: "arrow.up.forward.square") {
            if let url = URL(string: "https://x.com/i/lists") { NSWorkspace.shared.open(url) }
        })
        if let event = NSApp.currentEvent, let window = event.window,
           event.type == .leftMouseUp || event.type == .leftMouseDown {
            menu.popUp(positioning: nil, at: window.convertPoint(toScreen: event.locationInWindow), in: nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
    
    private func listRowVisual(isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: HomeFeedType.list.iconName)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .frame(width: 20)
            
            Text(loc.t("feed_list"))
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .opacity(0.7)
                .padding(.trailing, 10)
        }
        .foregroundColor(isSelected ? ThemeManager.accent : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.65)))
        .padding(.leading, 8.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
        .background {
            if isSelected {
                feedActiveBackground
            }
        }
    }
    
    // Quick switcher menu inside the active list banner
    private var listPickerMenu: some View {
        Menu {
            ForEach(timelineVM.userLists) { list in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        timelineVM.selectList(list)
                    }
                } label: {
                    HStack {
                        Image(systemName: list.iconName)
                        Text(list.name + (list.memberCount > 0 ? " · \(list.memberCount)" : ""))
                        if timelineVM.selectedListId == list.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                timelineVM.fetchUserLists()
            } label: {
                Label(loc.t("refresh_lists"), systemImage: "arrow.clockwise")
            }
            Button {
                if let url = URL(string: "https://x.com/i/lists") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(loc.t("manage_lists_on_x"), systemImage: "arrow.up.forward.square")
            }
        } label: {
            HStack(spacing: 2) {
                Text(loc.t("switch_list"))
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(ThemeManager.accent)
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    @ViewBuilder
    private var feedActiveBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : (theme.isLight ? Color.black : Color.white)
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.22))
                    : .regular
                Capsule(style: .continuous)
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? (theme.isLight ? 0.14 : 0.20) : (theme.isLight ? 0.08 : 0.14)))
                    .glassEffect(tabGlass, in: Capsule(style: .continuous))
                    .matchedGeometryEffect(id: "sidebar-home-feed", in: feedNamespace)
            } else {
                defaultFeedActiveBackground
            }
        } else {
            defaultFeedActiveBackground
        }
    }
    
    private var defaultFeedActiveBackground: some View {
        Capsule(style: .continuous)
            .fill(theme.isLight ? ThemeManager.accent.opacity(0.16) : ThemeManager.accent.opacity(0.24))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(ThemeManager.accent.opacity(theme.isLight ? 0.35 : 0.45), lineWidth: 0.6)
            )
            .matchedGeometryEffect(id: "sidebar-home-feed", in: feedNamespace)
    }
}

// MARK: - New Destination Placeholder View
struct NewDestinationPlaceholderView: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(ThemeManager.accent)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(ThemeManager.primaryText)
            Text("Native Liquid Glass destination")
                .font(.subheadline)
                .foregroundStyle(ThemeManager.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeManager.background.ignoresSafeArea())
    }
}

// MARK: - App Toast Notification Overlay
struct AppToastOverlay: View {
    @ObservedObject var toast = AppToastManager.shared
    
    var body: some View {
        if !toast.message.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    if let icon = toast.icon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(toast.message)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color(white: 0.12).opacity(0.95))
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 5)
                )
                .padding(.bottom, 36)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: toast.message)
            .allowsHitTesting(false)
        }
    }
}
