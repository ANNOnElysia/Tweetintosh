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
// Every Liquid Glass surface goes through here. It is Apple's glass as the HIG describes it, with no clarity control of
// the app's own: how clear or tinted the glass looks, and Reduce Transparency, are the user's choices in System Settings,
// which the system glass already follows.
@available(macOS 26.0, *)
private struct TweetGlassModifier<S: Shape>: ViewModifier {
    var glass: Glass
    var shape: S

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: shape)
    }
}

extension View {
    @available(macOS 26.0, *)
    func tweetGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        modifier(TweetGlassModifier(glass: glass, shape: shape))
    }
}

struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    var isLiquid: Bool
    var shape: S
    // Clear variant, so content behind stays visible (top tab switcher)
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

                // Nothing painted behind or around it: a fill sits between the glass and what it refracts and turns it
                // milky, and the system glass already draws its own edge and shadow
                content.tweetGlass(glassStyle, in: shape)
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
                    .padding(.top, 12) // The safe area already keeps the sidebar below the window controls.
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
            if nav.isSearchActive && (nav.sidebarExpanded || !nav.hasOverlay) {
                // Beside the sidebar's field when it is open, under the top bar's otherwise
                SearchSuggestionsPanel()
                    .padding(.top, nav.sidebarExpanded ? 70 : 66)
                    .padding(.leading, nav.sidebarExpanded ? 222 : 0)
                    .frame(maxWidth: .infinity, alignment: nav.sidebarExpanded ? .topLeading : .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    // Above any page open beside the sidebar
                    .zIndex(950)
            }
            
            // Full-pane pages (tweet detail, profiles), stacked newest on top
            ForEach(Array(nav.overlayStack.enumerated()), id: \.element.id) { index, entry in
                Group {
                    switch entry.page {
                    case .tweet(let tweet):
                        TweetDetailView(tweet: tweet) {
                            nav.dismissTweetDetail()
                        }
                        .environment(\.allowsVideoAutoplay, true)
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
                // Beside the sidebar when it is open, whose rows stay usable and lead back out of the page
                .padding(.leading, nav.sidebarExpanded ? 234 : 0)
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
            
            // Post three-dots floating options menu
            TweetOptionsMenuOverlay()
                .zIndex(8500)
            
            // Chat message deep-press / secondary-click menu
            DMMessageMenuOverlay()
                .zIndex(8600)
            
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
            HomeColumns(sidebarExpanded: nav.sidebarExpanded) {
                // Not in a NavigationStack: pages open through the app's own overlay stack, so it would navigate nowhere, and
                // it adds layers of layout that run again whenever the root is laid out
                MainTimelineView(onOpenSettings: onOpenSettings, onLoginRequest: onLoginRequest)
            }
        case .notifications:
            NavigationStack {
                NotificationsView(onOpenSettings: onOpenSettings, onLoginRequest: onLoginRequest)
            }
        case .messages:
            NavigationStack {
                MessagesView(onOpenSettings: onOpenSettings, onLoginRequest: onLoginRequest)
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
                            Group {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.iconName)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    Text(tabTitle(tab))
                                        .font(theme.appFont(size: 12.5, weight: isSelected ? .bold : .medium))
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
                            .pressDragItem(tab)
                        }
                    }
                    .pressDragSelection { (tab: AppTab) in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            selection = tab
                            nav.isSearchActive = false
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
                            .font(theme.appFont(size: 12.5))
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
                    .tweetGlass(glassStyle, in: Capsule())
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
                    .tweetGlass(tabGlass, in: Capsule())
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
    @ObservedObject private var accounts = AccountManager.shared
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
            
            SidebarSearchRow()
                .padding(.horizontal, 8)
            
            // Navigation Tabs
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        nav.closeAllPages()
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13.5, weight: isSelected ? .bold : .medium))
                            .foregroundColor(ThemeManager.accent)
                            .frame(width: 20)
                        
                        Text(tabTitle(tab))
                            .font(theme.appFont(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                        
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
            }
            
            SidebarContextSection(selection: $selection)
            
            Spacer(minLength: 0)
            
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
                        .font(theme.appFont(size: 13, weight: .semibold))
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
            
            // The signed-in account: the avatar and name open its profile, as they do everywhere else on X, and the gear
            // beside them opens Settings. Signed out, the whole row leads to Settings, where accounts are added.
            HStack(spacing: 4) {
                Button(action: openOwnProfile) {
                    HStack(spacing: 9) {
                        CurrentUserAvatar(size: 26)
                        Text(accounts.active?.name ?? loc.t("settings"))
                            .font(theme.appFont(size: 13, weight: .medium))
                            .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(loc.t(accounts.active == nil ? "settings" : "view_profile"))

                Button(action: onOpenSettings) {
                    Group {
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
                        } else {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12.5))
                                .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.60))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(loc.t("settings"))
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
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
    
    private func openOwnProfile() {
        guard let account = accounts.active else {
            onOpenSettings()
            return
        }
        nav.openProfile(TweetUser(id: account.id, name: account.name, screenName: account.screenName,
                                  avatarUrl: account.avatarUrl, isVerified: false))
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
                    .tweetGlass(tabGlass, in: Capsule(style: .continuous))
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

// MARK: - Sidebar Search

// A row until it is used, then the field itself, in place. Suggestions float beside the sidebar.
private struct SidebarSearchRow: View {
    @ObservedObject private var nav = NavigationManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Group {
            if nav.isSearchActive {
                field
            } else {
                Button { nav.toggleSearch() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(ThemeManager.accent)
                            .frame(width: 20)
                        Text(loc.t("tab_search"))
                            .font(theme.appFont(size: 13))
                            .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                        Spacer()
                        if nav.showShortcutBadges {
                            Text("⌥S")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(theme.isLight ? ThemeManager.tertiaryText : Color.white.opacity(0.40))
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: nav.isSearchActive) { _, active in
            if active {
                SearchSuggestionsModel.shared.update(query: nav.searchQuery)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { isFocused = true }
            } else {
                isFocused = false
                SearchSuggestionsModel.shared.reset()
            }
        }
    }
    
    private var field: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ThemeManager.accent)
            TextField(loc.t("search_placeholder"), text: $nav.searchQuery)
                .textFieldStyle(.plain)
                .font(theme.appFont(size: 12.5))
                .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                .focused($isFocused)
                .onSubmit { SearchSuggestionsModel.shared.submit(typed: nav.searchQuery) }
                .onChange(of: nav.searchQuery) { _, text in SearchSuggestionsModel.shared.update(query: text) }
                .onKeyPress(.downArrow) {
                    SearchSuggestionsModel.shared.move(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    SearchSuggestionsModel.shared.move(-1)
                    return .handled
                }
                .onExitCommand { nav.toggleSearch() }
            if !nav.searchQuery.isEmpty {
                Button { nav.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(Capsule(style: .continuous).fill(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.10)))
    }
}

// MARK: - Sidebar Context Section

// What can be chosen in the feed section. Each list counts as a feed of its own.
private enum SidebarFeedChoice: Hashable {
    case feed(HomeFeedType)
    case list(String)
}

// The middle of the sidebar follows the page: feeds for Home, filters for Notifications, nothing for Messages
private struct SidebarContextSection: View {
    @Binding var selection: AppTab
    @ObservedObject private var timelineVM = TimelineViewModel.shared
    @ObservedObject private var notifications = NotificationsViewModel.shared
    @ObservedObject private var nav = NavigationManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    
    var body: some View {
        Group {
            switch selection {
            case .home:
                section(title: loc.t("sidebar_feeds")) {
                    // Scrolls only when there are too many lists for the sidebar's height
                    ViewThatFits(in: .vertical) {
                        feedRows
                        ScrollView(showsIndicators: false) { feedRows }
                    }
                }
                .transition(.opacity)
            case .notifications:
                section(title: loc.t("sidebar_filter")) { filterRows }
                    .transition(.opacity)
            case .messages:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.18), value: selection)
    }
    
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(theme.appFont(size: 12.5, weight: .semibold))
                .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
                .padding(.horizontal, 11)
                .padding(.top, 10)
            content()
        }
    }
    
    private var feedRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach([HomeFeedType.forYou, .following, .bookmarks]) { type in
                    row(title: loc.t(type.titleKey), badge: type.shortcutLetter,
                        isSelected: timelineVM.selectedFeed == type) {
                        iconTile(type.iconName)
                    }
                    .pressDragItem(SidebarFeedChoice.feed(type))
                }
                ForEach(timelineVM.userLists) { list in
                    row(title: list.name, badge: nil,
                        isSelected: timelineVM.selectedFeed == .list && timelineVM.selectedListId == list.id) {
                        if let banner = list.bannerUrl {
                            CachedAsyncImage(urlString: banner, targetSize: CGSize(width: 26, height: 26))
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else {
                            iconTile(list.iconName)
                        }
                    }
                    .help(list.memberCount > 0 ? "\(list.name) · \(list.memberCount)" : list.name)
                    .pressDragItem(SidebarFeedChoice.list(list.id))
                }
            }
            .pressDragSelection { (choice: SidebarFeedChoice) in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    nav.closeAllPages()
                    switch choice {
                    case .feed(let type):
                        timelineVM.selectFeed(type)
                    case .list(let id):
                        if let list = timelineVM.userLists.first(where: { $0.id == id }) { timelineVM.selectList(list) }
                    }
                }
            }
            
            Button {
                if let url = URL(string: "https://x.com/i/lists") { NSWorkspace.shared.open(url) }
            } label: {
                row(title: loc.t("manage_lists_on_x"), badge: nil, isSelected: false, titleColor: ThemeManager.accent) {
                    iconTile("arrow.up.forward")
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(loc.t("refresh_lists")) { timelineVM.fetchUserLists() }
            }
        }
    }
    
    private var filterRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(NotificationFilter.allCases) { filter in
                row(title: loc.t(filter.titleKey), badge: filter.shortcutKey,
                    isSelected: notifications.selectedFilter == filter) {
                    iconTile(filter.iconName)
                }
                .pressDragItem(filter)
            }
        }
        .pressDragSelection { (filter: NotificationFilter) in
            nav.closeAllPages()
            notifications.selectFilter(filter)
        }
    }
    
    private func row<Icon: View>(title: String, badge: String?, isSelected: Bool, titleColor: Color? = nil,
                                 @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 9) {
            icon()
            Text(title)
                .font(theme.appFont(size: 13))
                .foregroundColor(titleColor ?? (theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92)))
                .lineLimit(1)
            Spacer(minLength: 0)
            if nav.showShortcutBadges, let badge = badge {
                Text(badge)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.isLight ? ThemeManager.tertiaryText : Color.white.opacity(0.40))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
    }
    
    private func iconTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.10))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(ThemeManager.accent)
            )
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
