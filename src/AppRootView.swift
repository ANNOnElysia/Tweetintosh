//
//  AppRootView.swift
//  MaX - Liquid Glass adaptive navigation shell
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
    @ObservedObject private var theme = ThemeManager.shared
    
    func body(content: Content) -> some View {
        if isLiquid {
            if #available(macOS 26.0, *) {
                // Mode A: Native Liquid Glass (SwiftUI macOS 26+ native API)
                // When tint is enabled: tints with theme accent; when disabled: pure clear transparent glass
                let glassStyle: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(0.16)).interactive()
                    : .regular.interactive()
                
                content
                    .glassEffect(glassStyle, in: shape)
                    .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 5)
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
                    VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)
                    Color(white: 0.08).opacity(0.42)
                }
                .clipShape(shape)
            )
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
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
            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 5)
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
                    .frame(width: 206)
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
            // Visible when sidebar is collapsed.
            // Leftmost button clicks to wake sidebar and capsule disappears.
            // Sidebar close button clicks to hide sidebar and capsule "卷土重来".
            if !nav.sidebarExpanded {
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
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: nav.sidebarExpanded)
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
                        .foregroundColor(Color.white.opacity(0.88))
                    
                    if nav.showShortcutBadges {
                        Text("⌥`")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, nav.showShortcutBadges ? 8 : 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 6)
            .help("Toggle Sidebar (⌥`)")
            
            // Subtle vertical divider
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 6)
            
            // 2. Center Content: Either the 3 Tabs OR the Inline Liquid Glass Search Field
            ZStack {
                if !nav.isSearchActive {
                    // Center Tabs: Home, Notifications, Messages
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
                                    
                                    if nav.showShortcutBadges {
                                        Text(tabShortcut(tab))
                                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                            .foregroundColor(isSelected ? ThemeManager.accent.opacity(0.85) : Color.white.opacity(0.40))
                                            .padding(.horizontal, 3.5)
                                            .padding(.vertical, 1.5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 3.5)
                                                    .fill(isSelected ? ThemeManager.accent.opacity(0.16) : Color.white.opacity(0.06))
                                            )
                                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                    }
                                }
                                .foregroundColor(isSelected ? ThemeManager.accent : Color.white.opacity(0.70))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
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
                            .foregroundColor(.white)
                            .focused($isSearchFocused)
                            .onExitCommand {
                                nav.toggleSearch()
                            }
                        
                        if !nav.searchQuery.isEmpty {
                            Button {
                                nav.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.55))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.trailing, 8)
                        } else {
                            Text("esc")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.40))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.08))
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        isSearchFocused = true
                    }
                } else {
                    isSearchFocused = false
                }
            }
            
            // Subtle vertical divider
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 6)
            
            // 3. Rightmost: Search Magnifying Glass / Close Button
            Button(action: {
                nav.toggleSearch()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: nav.isSearchActive ? "xmark" : "magnifyingglass")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(nav.isSearchActive ? ThemeManager.accent : Color.white.opacity(0.85))
                    
                    if nav.showShortcutBadges {
                        Text("⌥S")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(nav.isSearchActive ? ThemeManager.accent : Color.white.opacity(0.85))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(nav.isSearchActive ? ThemeManager.accent.opacity(0.16) : Color.white.opacity(0.12))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, nav.showShortcutBadges ? 8 : 8)
                .background {
                    if nav.isSearchActive {
                        Capsule().fill(Color.white.opacity(0.20))
                    } else {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 6)
            .help(nav.isSearchActive ? "Close Search (Esc / ⌥S)" : "Search (⌥S)")
        }
        .padding(.vertical, 4)
        .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Capsule()))
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: nav.showShortcutBadges)
        .fixedSize()
    }
    
    @ViewBuilder
    private var innerSearchGlassBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let glassStyle: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(0.18))
                    : .regular
                Capsule()
                    .fill(
                        theme.useLiquidGlassTint
                            ? ThemeManager.accent.opacity(0.12)
                            : Color.white.opacity(0.08)
                    )
                    .glassEffect(glassStyle, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
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
            .fill(Color.white.opacity(0.09))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
    }
    
    @ViewBuilder
    private var activeTabBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : Color.white
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(0.20))
                    : .regular
                Capsule()
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? 0.24 : 0.16))
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
            .fill(ThemeManager.accent.opacity(0.28))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.7)
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
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var selectionNamespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: App Logo + Sidebar Close Button
            HStack(alignment: .center) {
                Text("MaX")
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.92))
                
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
                                        .fill(ThemeManager.accent.opacity(0.15))
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .frame(height: 28)
                    .padding(.horizontal, nav.showShortcutBadges ? 6 : 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
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
                            .foregroundColor(isSelected ? ThemeManager.accent : Color.white.opacity(0.65))
                            .frame(width: 20)
                        
                        Text(tab.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? ThemeManager.accent : Color.white.opacity(0.75))
                        
                        Spacer()
                        
                        if nav.showShortcutBadges {
                            Text(tabShortcut(tab))
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? ThemeManager.accent.opacity(0.85) : Color.white.opacity(0.40))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 3.5)
                                        .fill(isSelected ? ThemeManager.accent.opacity(0.16) : Color.white.opacity(0.06))
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
            
            Spacer()
            
            // Bottom Settings Button
            Button(action: onOpenSettings) {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color.white.opacity(0.60))
                        .frame(width: 20)
                    Text("Settings")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color.white.opacity(0.70))
                    
                    Spacer()
                    
                    if nav.showShortcutBadges {
                        Text("⌘,")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.40))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))
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
                let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : Color.white
                let tabGlass: Glass = theme.useLiquidGlassTint
                    ? .regular.tint(ThemeManager.accent.opacity(0.22))
                    : .regular
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tintColor.opacity(theme.useLiquidGlassTint ? 0.20 : 0.14))
                    .glassEffect(tabGlass, in: .rect(cornerRadius: 10))
                    .matchedGeometryEffect(id: "sidebar-active-tab", in: selectionNamespace)
            } else {
                defaultSidebarActiveTabBackground
            }
        } else {
            defaultSidebarActiveTabBackground
        }
    }
    
    private var defaultSidebarActiveTabBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(ThemeManager.accent.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                    .allowsHitTesting(false)
            )
            .matchedGeometryEffect(id: "sidebar-active-tab", in: selectionNamespace)
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
