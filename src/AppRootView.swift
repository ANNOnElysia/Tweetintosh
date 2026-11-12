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

// MARK: - Top Bar Targets

// The top bar's controls are small and sit near the top edge, so a finger reaches for them from below and often lands
// beside them. Each takes taps across the full height of the bar plus this much space above and below it; the space is
// given back outside, so nothing moves.
enum TopBarTarget {
    static let above: CGFloat = 10
    static let below: CGFloat = 16
}

private extension View {
    // Inside a top bar button's label
    func topBarTarget() -> some View {
        padding(.top, TopBarTarget.above + 4)
            .padding(.bottom, TopBarTarget.below + 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
    }

    // Outside the same button
    func topBarTargetSpace() -> some View {
        padding(.top, -(TopBarTarget.above + 4))
            .padding(.bottom, -(TopBarTarget.below + 4))
            .padding(.horizontal, -4)
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
    // Interactive glass answers a press itself, which suits glass that is a control. A bar or panel holding other
    // controls passes false: on a touch screen its own response to a finger took the touch from the tab or button on it.
    var isInteractive: Bool = true
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        if isLiquid {
            if #available(macOS 26.0, *) {
                // Mode A: Native Liquid Glass (SwiftUI macOS 26+ native API)
                let base: Glass = isClear ? .clear : .regular
                let tinted: Glass = theme.useLiquidGlassTint
                    ? base.tint(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.16))
                    : base
                let glassStyle: Glass = isInteractive ? tinted.interactive() : tinted

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

// MARK: - Sidebar Glass Transition

// One timing for the sidebar, the top capsule and the page beside them, so the shapes and the layout move together.
// Apple Music on iPad settles both in about a quarter of a second with a spring, not a long ease: the droplet has
// travelled and the new row is highlighted before a 0.45 s curve would still be halfway there.
// Shared with NavigationManager, whose keyboard shortcut and automatic expansion toggle the same state.
enum SidebarMotion {
    static let toggle = Animation.spring(response: 0.28, dampingFraction: 0.90)
    // The selected tab's glass capsule on its own, which has less distance to cover than the sidebar.
    static let selection = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let content = Animation.spring(response: 0.24, dampingFraction: 0.88)
}

private struct SidebarChromeMotion: AnimatableModifier {
    var progress: CGFloat
    let capsuleFrame: CGRect
    let sidebarFrame: CGRect
    let toggleWidth: CGFloat
    let isGlass: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let start = CGPoint(x: capsuleFrame.minX + 6 + toggleWidth / 2, y: capsuleFrame.midY)
        // The selected tab's background sits 8 points in from the sidebar's edge (the row's horizontal inset); the
        // toggle rests on that same edge instead of the header's wider padding, so the two line up.
        let end = CGPoint(x: sidebarFrame.maxX - 8 - toggleWidth / 2, y: sidebarFrame.minY + 26)
        let bend = min(40, abs(end.x - start.x) * 0.2)
        // A spring can overshoot its target; the path's end point is a resting position, so hold it there.
        let t = min(max(progress, 0), 1)
        let u = 1 - t
        let x = u * start.x + t * end.x
        let y = u * u * start.y + 2 * u * t * (max(start.y, end.y) + bend) + t * t * end.y
        let width = u * capsuleFrame.width + t * sidebarFrame.width
        let height = u * capsuleFrame.height + t * sidebarFrame.height

        // Keep the glass attached to the moving button rather than interpolating an unrelated screen position.
        content
            .frame(width: isGlass ? width : nil, height: isGlass ? height : nil)
            .position(
                x: x + (isGlass ? u * (capsuleFrame.midX - start.x) + t * (sidebarFrame.midX - end.x) : 0),
                y: y + (isGlass ? u * (capsuleFrame.midY - start.y) + t * (sidebarFrame.midY - end.y) : 0)
            )
    }
}

// MARK: - AppRootView (Adaptive Shell)

// The floating sidebar's column. The leading margin is wider than the window-edge margins so the system glass shadow
// has room on the left; the width shrinks by the same amount, keeping the right edge where it was so the timeline does
// not move. The trailing and bottom margins give the shadow room before it is cut off by the page and the window edge.
enum SidebarLayout {
    static let width: CGFloat = 208
    static let leadingMargin: CGFloat = 20
    static let trailingMargin: CGFloat = 32
    static let bottomMargin: CGFloat = 32
    static let columnWidth = leadingMargin + width + trailingMargin
}

struct AppRootView: View {
    @Bindable private var nav = NavigationManager.shared
    @ObservedObject private var paneLayout = DetailPane.shared.layout
    // The root background does not follow the window's appearance on its own: it reads the theme's resolved colour
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var capsuleSize: CGSize = .zero
    @State private var toggleWidth: CGFloat = 0
    var onOpenSettings: () -> Void = {}
    var onLoginRequest: () -> Void = {}

    private var capsuleVisible: Bool {
        !nav.sidebarExpanded && !nav.hasOverlay && !nav.isVideosChromeHidden
    }

    // One persistent surface moves between the two layouts. Its controls stay outside the glass's captured content.
    private var sidebarChromeGlass: some View {
        Rectangle()
            .fill(.clear)
            .modifier(
                AdaptiveGlassModifier(
                    isLiquid: theme.useLiquidGlass,
                    shape: .rect(cornerRadius: 22),
                    isInteractive: false
                )
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var sidebarToggleButton: some View {
        Button { nav.sidebarExpanded.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                if nav.showShortcutBadges {
                    Text("⌥`")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 3.5).fill(ThemeManager.accent.opacity(0.12)))
                }
            }
            .foregroundColor(nav.sidebarExpanded ? ThemeManager.accent : ThemeManager.primaryText)
            .frame(height: 32)
            .padding(.horizontal, 8)
            .background(Capsule().fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08)))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { toggleWidth = $0 }
            .topBarTarget()
        }
        .buttonStyle(.target)
        .topBarTargetSpace()
        .help(loc.t("tooltip_toggle_sidebar"))
        .accessibilityLabel(loc.t("menu_toggle_sidebar"))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ThemeManager.background
                .ignoresSafeArea()
            
            GeometryReader { geometry in
                let sidebarFrame = CGRect(
                    x: SidebarLayout.leadingMargin, y: 12,
                    width: SidebarLayout.width,
                    height: max(0, geometry.size.height - 12 - SidebarLayout.bottomMargin)
                )
                let columnWidth = capsuleColumnWidth(in: geometry.size.width)
                let capsuleFrame = CGRect(
                    x: (columnWidth - capsuleSize.width) / 2, y: 14,
                    width: capsuleSize.width, height: capsuleSize.height
                )

                ZStack(alignment: .topLeading) {
                    destination
                        .padding(.leading, nav.sidebarExpanded ? SidebarLayout.columnWidth : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    sidebarChromeGlass
                        .modifier(SidebarChromeMotion(
                            progress: nav.sidebarExpanded ? 1 : 0,
                            capsuleFrame: capsuleFrame, sidebarFrame: sidebarFrame,
                            toggleWidth: toggleWidth, isGlass: true
                        ))
                        .opacity((nav.sidebarExpanded || capsuleVisible) && !capsuleFrame.isEmpty ? 1 : 0)
                        .animation(reduceMotion ? nil : SidebarMotion.toggle, value: nav.sidebarExpanded)

                    if nav.sidebarExpanded {
                        LiquidGlassSidebar(
                            selection: $nav.currentTab,
                            toggleWidth: toggleWidth,
                            onOpenSettings: onOpenSettings
                        )
                        .frame(width: sidebarFrame.width, height: sidebarFrame.height)
                        .position(x: sidebarFrame.midX, y: sidebarFrame.midY)
                        .transition(.opacity)
                        .zIndex(1)
                    }

                    // Keep the hidden bar laid out so its intrinsic size is ready before the glass moves back to it.
                    LiquidGlassCapsule(
                        selection: $nav.currentTab,
                        toggleWidth: toggleWidth
                    )
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { capsuleSize = $0 }
                    .padding(.top, 14)
                    .frame(width: columnWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(capsuleVisible ? 1 : 0)
                    .allowsHitTesting(capsuleVisible)
                    .accessibilityHidden(!capsuleVisible)
                    .animation(reduceMotion ? nil : SidebarMotion.content, value: capsuleVisible)
                    .zIndex(1)

                    // The same button leads the transition; both content layouts reserve its resting position.
                    sidebarToggleButton
                        .modifier(SidebarChromeMotion(
                            progress: nav.sidebarExpanded ? 1 : 0,
                            capsuleFrame: capsuleFrame, sidebarFrame: sidebarFrame,
                            toggleWidth: toggleWidth, isGlass: false
                        ))
                        .animation(reduceMotion ? nil : SidebarMotion.toggle, value: nav.sidebarExpanded)
                        .opacity(nav.sidebarExpanded || capsuleVisible ? 1 : 0)
                        .allowsHitTesting(nav.sidebarExpanded || capsuleVisible)
                        .accessibilityHidden(!nav.sidebarExpanded && !capsuleVisible)
                        .zIndex(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : SidebarMotion.toggle, value: nav.sidebarExpanded)
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
                .padding(.leading, nav.sidebarExpanded ? SidebarLayout.columnWidth : 0)
                .animation(reduceMotion ? nil : SidebarMotion.toggle, value: nav.sidebarExpanded)
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
        .sheet(isPresented: $nav.isShowingCompose) {
            TweetComposerSheet(quotedTweet: nav.composeQuotedTweet)
        }
        .sheet(item: $nav.replyTargetTweet) { tweet in
            ReplyComposerSheet(tweet: tweet)
        }
    }

    // The sidebar is closed whenever the bar shows, so Home's columns span the whole window
    private func capsuleColumnWidth(in windowWidth: CGFloat) -> CGFloat {
        guard nav.currentTab == .home, paneLayout.isAvailable else { return windowWidth }
        return HomeColumns<EmptyView>.timelineWidth(in: windowWidth, paneAvailable: true)
    }

    @ViewBuilder private var destination: some View {
        switch nav.currentTab {
        case .home:
            HomeColumns {
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
        case .videos:
            VideosView()
                .environment(\.peekScope, .videos)
        }
    }
}

struct DraggingSelectionBackground<S: Shape>: View {
    let shape: S
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        shape.fill(Color.clear)
            .modifier(AdaptiveGlassModifier(
                isLiquid: theme.useLiquidGlass, shape: shape, isClear: true, isInteractive: false
            ))
    }
}

// The selected background used by the sidebar tabs, feeds and filters. The shape decides whether it
// reads as the tab capsule or a list row.
private struct SidebarActiveBackground<S: Shape>: View {
    let shape: S
    @ObservedObject private var theme = ThemeManager.shared

    @ViewBuilder
    var body: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : (theme.isLight ? Color.black : Color.white)
                let glass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.14 : 0.22))
                    : .regular
                shape
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? (theme.isLight ? 0.14 : 0.20) : (theme.isLight ? 0.08 : 0.14)))
                    .tweetGlass(glass, in: shape)
            } else {
                fallback
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        shape
            .fill(theme.isLight ? ThemeManager.accent.opacity(0.16) : ThemeManager.accent.opacity(0.22))
            .overlay(
                shape
                    .stroke(theme.isLight ? ThemeManager.accent.opacity(0.35) : Color.white.opacity(0.18), lineWidth: 0.6)
                    .allowsHitTesting(false)
            )
    }
}

// MARK: - Top Floating Capsule (Horizontal Droplet)
private struct LiquidGlassCapsule: View {
    @Binding var selection: AppTab
    var toggleWidth: CGFloat
    @Bindable var nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewTab: PressDragPreview<AppTab>?
    
    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: toggleWidth, height: 32)
                .padding(.leading, 6)
            
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
                        ForEach(AppTab.available) { tab in
                            let isSelected = (previewTab?.id ?? selection) == tab
                            let isCurrentTab = selection == tab
                            Group {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.iconName)
                                        .font(.system(size: 12, weight: isCurrentTab ? .bold : .medium))
                                    Text(tabTitle(tab))
                                        .font(theme.appFont(size: 12.5, weight: isCurrentTab ? .bold : .medium))
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
                                .layoutPriority(isCurrentTab ? 2 : 1)
                                .contentShape(Rectangle())
                            }
                            .pressDragItem(tab)
                            .accessibilityAddTraits(isCurrentTab ? [.isSelected] : [])
                        }
                    }
                    .pressDragSelectionSurface(
                        selection: selection, preview: previewTab
                    ) {
                        if previewTab != nil {
                            DraggingSelectionBackground(shape: Capsule())
                        } else {
                            activeTabBackground
                        }
                    }
                    // The whole height of the bar and the space around it picks the nearest tab
                    .padding(.top, TopBarTarget.above + 4)
                    .padding(.bottom, TopBarTarget.below + 4)
                    .pressDragSelection(preview: $previewTab, axis: .horizontal) { (tab: AppTab) in
                        nav.refreshSelectedTab(tab)
                        withAnimation(reduceMotion ? nil : SidebarMotion.selection) {
                            selection = tab
                            nav.isSearchActive = false
                        }
                    }
                    .animation(reduceMotion ? nil : SidebarMotion.selection, value: previewTab == nil)
                    .animation(reduceMotion ? nil : SidebarMotion.selection, value: selection)
                    .padding(.top, -(TopBarTarget.above + 4))
                    .padding(.bottom, -(TopBarTarget.below + 4))
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
                            .buttonStyle(.target)
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
                .topBarTarget()
            }
            .buttonStyle(.target)
            .topBarTargetSpace()
            .padding(.trailing, 6)
            .help(nav.isSearchActive ? "Close Search (Esc / ⌥S)" : "Search (⌥S)")
        }
        .padding(.vertical, 4)
        .animation(SidebarMotion.content, value: nav.showShortcutBadges)
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
        case .videos:
            let t = loc.t("tab_videos")
            return t.isEmpty ? "Videos" : t
        }
    }
    
    private func tabShortcut(_ tab: AppTab) -> String {
        switch tab {
        case .home: return "⌥1"
        case .notifications: return "⌥2"
        case .messages: return "⌥3"
        case .videos: return "⌥4"
        }
    }
}

// MARK: - Floating Vertical Sidebar Droplet (Dual-Mode: Floating Liquid Glass vs Frosted Glass)
private struct LiquidGlassSidebar: View {
    @Binding var selection: AppTab
    var toggleWidth: CGFloat
    var onOpenSettings: () -> Void
    let nav = NavigationManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject private var accounts = AccountManager.shared
    @State private var previewTab: PressDragPreview<AppTab>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: App Logo + Sidebar Close Button
            HStack(alignment: .center) {
                Text("Tweetintosh")
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                
                Spacer()
                
                Color.clear.frame(width: toggleWidth, height: 32)
            }
            .padding(.horizontal, 19)
            .padding(.top, 10)
            // The header sits 4 points higher, nearer the 22-point corner, and the rows below follow it up; the
            // compose button and the account row stay pinned to the bottom.
            .padding(.bottom, 6)
            
            SidebarSearchRow()
                .padding(.horizontal, 8)
            
            // Navigation Tabs
            VStack(alignment: .leading, spacing: 8) {
                ForEach(AppTab.available) { tab in
                    let isSelected = (previewTab?.id ?? selection) == tab
                    let isCurrentTab = selection == tab
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13.5, weight: isCurrentTab ? .bold : .medium))
                            .foregroundColor(ThemeManager.accent)
                            .frame(width: 20)
                        
                        Text(tabTitle(tab))
                            .font(theme.appFont(size: 13, weight: isCurrentTab ? .semibold : .regular))
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
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                    .pressDragItem(tab)
                    .accessibilityAddTraits(isCurrentTab ? [.isSelected] : [])
                }
            }
            .pressDragSelectionSurface(
                selection: selection, preview: previewTab
            ) {
                if previewTab != nil {
                    DraggingSelectionBackground(shape: Capsule(style: .continuous))
                } else {
                    SidebarActiveBackground(shape: Capsule(style: .continuous))
                }
            }
            .pressDragSelection(preview: $previewTab, axis: .vertical) { (tab: AppTab) in
                nav.refreshSelectedTab(tab)
                withAnimation(reduceMotion ? nil : SidebarMotion.selection) {
                    nav.closeAllPages()
                    selection = tab
                }
            }
            .animation(reduceMotion ? nil : SidebarMotion.selection, value: previewTab == nil)
            .animation(reduceMotion ? nil : SidebarMotion.selection, value: selection)
            .padding(.horizontal, 8)
            
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
            .buttonStyle(.target)
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
                .buttonStyle(.target)
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
                .buttonStyle(.target)
                .help(loc.t("settings"))
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .frame(maxHeight: .infinity)
        .animation(SidebarMotion.content, value: nav.showShortcutBadges)
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
        case .videos:
            let t = loc.t("tab_videos")
            return t.isEmpty ? "Videos" : t
        }
    }
    
    private func tabShortcut(_ tab: AppTab) -> String {
        switch tab {
        case .home: return "⌥1"
        case .notifications: return "⌥2"
        case .messages: return "⌥3"
        case .videos: return "⌥4"
        }
    }
    
}

// MARK: - Sidebar Search

// A row until it is used, then the field itself, in place. Suggestions float beside the sidebar.
private struct SidebarSearchRow: View {
    @Bindable private var nav = NavigationManager.shared
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
                .buttonStyle(.target)
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
                .buttonStyle(.target)
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
    private let timelineVM = TimelineViewModel.shared
    @ObservedObject private var notifications = NotificationsViewModel.shared
    private let nav = NavigationManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var feedPreview: PressDragPreview<SidebarFeedChoice>?
    @State private var filterPreview: PressDragPreview<NotificationFilter>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
            case .messages, .videos:
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
    
    private var selectedFeedChoice: SidebarFeedChoice? {
        timelineVM.selectedFeed == .list
            ? .list(timelineVM.selectedListId)
            : .feed(timelineVM.selectedFeed)
    }

    private var feedRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach([HomeFeedType.forYou, .following, .bookmarks]) { type in
                    row(title: loc.t(type.titleKey), badge: type.shortcutLetter,
                        isPreviewed: feedPreview?.id == .feed(type)) {
                        iconTile(type.iconName)
                    }
                    .pressDragItem(SidebarFeedChoice.feed(type))
                    .accessibilityAddTraits(timelineVM.selectedFeed == type ? [.isSelected] : [])
                }
                ForEach(timelineVM.userLists) { list in
                    row(title: list.name, badge: nil,
                        isPreviewed: feedPreview?.id == .list(list.id)) {
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
                    .accessibilityAddTraits(timelineVM.selectedFeed == .list && timelineVM.selectedListId == list.id ? [.isSelected] : [])
                }
            }
            .pressDragSelectionSurface(
                selection: selectedFeedChoice, preview: feedPreview
            ) {
                SidebarActiveBackground(shape: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .pressDragSelection(preview: $feedPreview, axis: .vertical) { (choice: SidebarFeedChoice) in
                withAnimation(reduceMotion ? nil : SidebarMotion.selection) {
                    nav.closeAllPages()
                    switch choice {
                    case .feed(let type):
                        timelineVM.selectFeed(type)
                    case .list(let id):
                        if let list = timelineVM.userLists.first(where: { $0.id == id }) { timelineVM.selectList(list) }
                    }
                }
            }
            .animation(reduceMotion ? nil : SidebarMotion.selection, value: feedPreview == nil)
            .animation(reduceMotion ? nil : SidebarMotion.selection, value: selectedFeedChoice)
            
            Button {
                if let url = URL(string: "https://x.com/i/lists") { NSWorkspace.shared.open(url) }
            } label: {
                row(title: loc.t("manage_lists_on_x"), badge: nil, titleColor: ThemeManager.accent) {
                    iconTile("arrow.up.forward")
                }
            }
            .buttonStyle(.target)
            .contextMenu {
                Button(loc.t("refresh_lists")) { timelineVM.fetchUserLists() }
            }
        }
    }
    
    private var filterRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(NotificationFilter.allCases) { filter in
                row(title: loc.t(filter.titleKey), badge: filter.shortcutKey,
                    isPreviewed: filterPreview?.id == filter) {
                    iconTile(filter.iconName)
                }
                .pressDragItem(filter)
                .accessibilityAddTraits(notifications.selectedFilter == filter ? [.isSelected] : [])
            }
        }
        .pressDragSelectionSurface(
            selection: notifications.selectedFilter, preview: filterPreview
        ) {
            SidebarActiveBackground(shape: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .pressDragSelection(preview: $filterPreview, axis: .vertical) { (filter: NotificationFilter) in
            nav.closeAllPages()
            notifications.selectFilter(filter)
        }
        .animation(reduceMotion ? nil : SidebarMotion.selection, value: filterPreview == nil)
        .animation(reduceMotion ? nil : SidebarMotion.selection, value: notifications.selectedFilter)
    }
    
    private func row<Icon: View>(title: String, badge: String?, isPreviewed: Bool = false, titleColor: Color? = nil,
                                 @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 9) {
            icon()
            Text(title)
                .font(theme.appFont(size: 13))
                .foregroundColor(titleColor ?? (isPreviewed ? ThemeManager.accent : (theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))))
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
        .frame(minHeight: 36)
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
    @ObservedObject private var theme = ThemeManager.shared
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
