//
//  TweetOptionsMenu.swift
//  Tweetintosh
//
//  Floating Liquid Glass action menu for posts complying with macOS Human Interface Guidelines (HIG).
//  Features smooth spring animations, responsive hover highlights, smart edge avoidance,
//  and automatic seamless dismissal on scroll allowing continuous timeline browsing.
//

import SwiftUI
import AppKit

// MARK: - Menu Payload & Manager
struct TweetMenuPayload: Identifiable {
    let id = UUID()
    let tweet: Tweet
    let anchorRect: CGRect
    let onToggleBookmark: (() -> Void)?
}

final class TweetOptionsMenuManager: ObservableObject {
    static let shared = TweetOptionsMenuManager()
    
    @Published var activeMenu: TweetMenuPayload?
    var menuCardFrame: CGRect = .zero
    
    private var eventMonitor: Any?
    
    private init() {}
    
    func present(tweet: Tweet, anchorRect: CGRect, onToggleBookmark: (() -> Void)?) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
            self.activeMenu = TweetMenuPayload(
                tweet: tweet,
                anchorRect: anchorRect,
                onToggleBookmark: onToggleBookmark
            )
        }
        startMonitoring()
    }
    
    func dismiss() {
        guard activeMenu != nil else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            self.activeMenu = nil
        }
        stopMonitoring()
    }
    
    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self = self, self.activeMenu != nil else { return event }
            
            switch event.type {
            case .scrollWheel:
                // User started scrolling: immediately dismiss the menu and allow the scroll event to pass through
                self.dismiss()
                return event
                
            case .leftMouseDown, .rightMouseDown:
                // Check if click occurred outside the floating menu card
                if let window = event.window {
                    let locInWindow = event.locationInWindow
                    // Convert card frame from AppWindow coordinate space
                    if !self.menuCardFrame.isEmpty && self.menuCardFrame.contains(CGPoint(x: locInWindow.x, y: window.frame.height - locInWindow.y)) {
                        // Click is inside the menu: let SwiftUI handle it
                        return event
                    }
                }
                // Click is outside: dismiss the menu
                self.dismiss()
                return event
                
            case .keyDown:
                // Esc key dismisses the menu
                if event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                return event
                
            default:
                return event
            }
        }
    }
    
    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Options Button (Placed in post headers)
private final class ButtonHoverState: ObservableObject {
    @Published var isHovered = false
}

struct TweetOptionsMenuButton: View {
    let tweet: Tweet
    var onToggleBookmark: (() -> Void)? = nil
    
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var menuManager = TweetOptionsMenuManager.shared
    @StateObject private var hover = ButtonHoverState()
    
    private var isMenuOpen: Bool {
        menuManager.activeMenu?.tweet.id == tweet.id
    }
    
    var body: some View {
        GeometryReader { proxy in
            Button(action: {
                let rect = proxy.frame(in: .named("AppWindow"))
                if isMenuOpen {
                    menuManager.dismiss()
                } else {
                    menuManager.present(tweet: tweet, anchorRect: rect, onToggleBookmark: onToggleBookmark)
                }
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(
                        isMenuOpen || hover.isHovered
                            ? (theme.isLight ? ThemeManager.primaryText : Color.white)
                            : (theme.isLight ? ThemeManager.secondaryText.opacity(0.8) : Color.white.opacity(0.55))
                    )
                    .rotationEffect(.degrees(isMenuOpen ? 90 : 0))
                    .scaleEffect(isMenuOpen ? 1.05 : (hover.isHovered ? 1.10 : 1.0))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                isMenuOpen
                                    ? (theme.isLight ? Color.black.opacity(0.09) : Color.white.opacity(0.18))
                                    : (hover.isHovered
                                        ? (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                                        : Color.clear)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hover.isHovered)
            .animation(.spring(response: 0.32, dampingFraction: 0.75), value: isMenuOpen)
            .onHover { isHovered in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    hover.isHovered = isHovered
                }
            }
            .help(loc.t("more_actions"))
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Global Floating Menu Overlay (Rendered in AppRootView)
struct TweetOptionsMenuOverlay: View {
    @ObservedObject var manager = TweetOptionsMenuManager.shared
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        GeometryReader { windowGeo in
            if let payload = manager.activeMenu {
                // Dimless backdrop to catch outside taps without darkening the screen
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        manager.dismiss()
                    }
                
                floatingCard(payload: payload, containerSize: windowGeo.size)
            }
        }
        .allowsHitTesting(manager.activeMenu != nil)
    }
    
    @ViewBuilder
    private func floatingCard(payload: TweetMenuPayload, containerSize: CGSize) -> some View {
        let menuWidth: CGFloat = 200
        let approxMenuHeight: CGFloat = 240
        let anchor = payload.anchorRect
        
        // Smart edge positioning: determine if menu should open downward or upward
        let opensUpward = anchor.maxY + approxMenuHeight > containerSize.height - 16
        let xPos = min(max(anchor.maxX - menuWidth, 12), containerSize.width - menuWidth - 12)
        let yPos = opensUpward ? max(anchor.minY - approxMenuHeight - 4, 12) : anchor.maxY + 4
        
        TweetMenuContentView(
            tweet: payload.tweet,
            onToggleBookmark: payload.onToggleBookmark,
            onDismiss: { manager.dismiss() }
        )
        .frame(width: menuWidth)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("AppWindow"))
        } action: { frame in
            manager.menuCardFrame = frame
        }
        .position(x: xPos + menuWidth / 2.0, y: yPos + approxMenuHeight / 2.0)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.88, anchor: opensUpward ? .bottomTrailing : .topTrailing)
                    .combined(with: .opacity),
                removal: .scale(scale: 0.94, anchor: opensUpward ? .bottomTrailing : .topTrailing)
                    .combined(with: .opacity)
            )
        )
    }
}

// MARK: - Floating Menu Content View
private struct TweetMenuContentView: View {
    let tweet: Tweet
    var onToggleBookmark: (() -> Void)?
    var onDismiss: () -> Void
    
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    
    private var isSelf: Bool {
        let activeId = AccountManager.shared.activeId
        let activeAccount = AccountManager.shared.accounts.first { $0.id == activeId }
        if let acc = activeAccount {
            if !tweet.author.id.isEmpty && tweet.author.id == acc.id { return true }
            if !acc.screenName.isEmpty && tweet.author.screenName.caseInsensitiveCompare(acc.screenName) == .orderedSame { return true }
        }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 1. Bookmark
            menuRow(
                title: loc.t(tweet.isBookmarked ? "remove_bookmark" : "bookmark"),
                icon: tweet.isBookmarked ? "bookmark.fill" : "bookmark",
                accentColor: ThemeManager.accent
            ) {
                let willBookmark = !tweet.isBookmarked
                onDismiss()
                if let onToggle = onToggleBookmark {
                    onToggle()
                } else {
                    TimelineViewModel.shared.toggleBookmark(for: tweet)
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                AppToastManager.shared.show(
                    loc.t(willBookmark ? "bookmarked" : "remove_bookmark"),
                    icon: willBookmark ? "bookmark.fill" : "bookmark"
                )
            }
            
            // 2. Copy Link
            menuRow(
                title: loc.t("copy_link"),
                icon: "link",
                accentColor: theme.isLight ? ThemeManager.primaryText : .white
            ) {
                onDismiss()
                let url = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                AppToastManager.shared.show(loc.t("link_copied"), icon: "checkmark.circle.fill")
            }
            
            // 3. Share...
            menuRow(
                title: loc.t("share"),
                icon: "square.and.arrow.up",
                accentColor: ThemeManager.accent
            ) {
                onDismiss()
                let urlStr = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
                if let url = URL(string: urlStr) {
                    let picker = NSSharingServicePicker(items: [url])
                    if let window = NSApp.keyWindow, let contentView = window.contentView {
                        let mouseLoc = window.mouseLocationOutsideOfEventStream
                        picker.show(relativeTo: NSRect(x: mouseLoc.x, y: mouseLoc.y, width: 1, height: 1), of: contentView, preferredEdge: .minY)
                    }
                }
            }
            
            // 4. Open in Browser
            menuRow(
                title: loc.t("open_in_browser"),
                icon: "safari",
                accentColor: Color(hex: "#00BA7C")
            ) {
                onDismiss()
                if let url = URL(string: "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            // Moderation actions if not self
            if !isSelf {
                Divider()
                    .background(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
                    .padding(.vertical, 3)
                
                // 5. Mute @handle
                menuRow(
                    title: loc.format("post_menu_mute", ["handle": tweet.author.formattedHandle]),
                    icon: "speaker.slash",
                    accentColor: Color(hex: "#FF8A00")
                ) {
                    onDismiss()
                    APIClient.shared.muteUser(userId: tweet.author.id, screenName: tweet.author.screenName) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                TimelineViewModel.shared.removeTweets(byAuthorId: tweet.author.id, screenName: tweet.author.screenName)
                                AppToastManager.shared.show(
                                    loc.format("post_muted_toast", ["handle": tweet.author.formattedHandle]),
                                    icon: "speaker.slash.fill"
                                )
                            case .failure(let error):
                                AppToastManager.shared.show(error.localizedDescription, icon: "xmark.circle")
                            }
                        }
                    }
                }
                
                // 6. Block @handle
                menuRow(
                    title: loc.format("post_menu_block", ["handle": tweet.author.formattedHandle]),
                    icon: "nosign",
                    accentColor: Color(hex: "#F91880")
                ) {
                    onDismiss()
                    APIClient.shared.blockUser(userId: tweet.author.id, screenName: tweet.author.screenName) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                BlockedByRegistry.shared.insert(tweet.author.id)
                                TimelineViewModel.shared.removeTweets(byAuthorId: tweet.author.id, screenName: tweet.author.screenName)
                                AppToastManager.shared.show(
                                    loc.format("post_blocked_toast", ["handle": tweet.author.formattedHandle]),
                                    icon: "nosign"
                                )
                            case .failure(let error):
                                AppToastManager.shared.show(error.localizedDescription, icon: "xmark.circle")
                            }
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    theme.isLight
                        ? Color(hex: "#FDFDFD").opacity(0.96)
                        : Color(hex: "#1E2024").opacity(0.96)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.14),
                            lineWidth: 0.7
                        )
                )
                .shadow(
                    color: Color.black.opacity(theme.isLight ? 0.14 : 0.40),
                    radius: 18,
                    x: 0,
                    y: 8
                )
        )
    }
    
    private func menuRow(title: String, icon: String, accentColor: Color, action: @escaping () -> Void) -> some View {
        MenuRowButton(title: title, icon: icon, accentColor: accentColor, action: action)
    }
}

private final class RowHoverState: ObservableObject {
    @Published var isHovered = false
}

private struct MenuRowButton: View {
    let title: String
    let icon: String
    let accentColor: Color
    let action: () -> Void
    
    @ObservedObject var theme = ThemeManager.shared
    @StateObject private var hover = RowHoverState()
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(accentColor)
                    .frame(width: 18, alignment: .center)
                
                Text(title)
                    .font(theme.appFont(size: 12.5, weight: .medium))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        hover.isHovered
                            ? (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.20, dampingFraction: 0.80), value: hover.isHovered)
        .onHover { isHovered in
            withAnimation(.spring(response: 0.20, dampingFraction: 0.80)) {
                hover.isHovered = isHovered
            }
        }
    }
}
