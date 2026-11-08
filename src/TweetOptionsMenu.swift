//
//  TweetOptionsMenu.swift
//  Tweetintosh
//
//  Floating Context Menu for posts strictly conforming to Apple Human Interface Guidelines (HIG).
//  Implements official Apple-grade spring scale/fade animations, adaptive frosted glass / Liquid Glass,
//  flattened menu hierarchy (no submenus), and seamless auto-dismiss on scroll.
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
        withAnimation(.easeOut(duration: 0.15)) {
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
// Which post is hovered rather than a flag, so a reused table cell doesn't carry the highlight to its next post
private final class ButtonHoverState: ObservableObject {
    @Published var hoveredId: String?
}

struct TweetOptionsMenuButton: View {
    let tweet: Tweet
    var onToggleBookmark: (() -> Void)? = nil
    
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var menuManager = TweetOptionsMenuManager.shared
    @StateObject private var hover = ButtonHoverState()
    @StateObject private var frameBox = FrameBox()
    
    private var isMenuOpen: Bool {
        menuManager.activeMenu?.tweet.id == tweet.id
    }
    
    private var isHovered: Bool { hover.hoveredId == tweet.id }
    
    var body: some View {
        Group {
            Button(action: {
                // Read from AppKit: the "AppWindow" space can't be reached from inside a table cell's own hosting view
                let rect = frameBox.liveRect
                if isMenuOpen {
                    menuManager.dismiss()
                } else {
                    menuManager.present(tweet: tweet, anchorRect: rect, onToggleBookmark: onToggleBookmark)
                }
            }) {
                // Static three dots adhering to official Apple HIG (no 90-degree rotation)
                Image(systemName: "ellipsis")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(
                        isMenuOpen || isHovered
                            ? (theme.isLight ? ThemeManager.primaryText : Color.white)
                            : (theme.isLight ? ThemeManager.secondaryText.opacity(0.80) : Color.white.opacity(0.55))
                    )
                    .scaleEffect(isMenuOpen ? 1.05 : (isHovered ? 1.08 : 1.0))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                isMenuOpen
                                    ? (theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.16))
                                    : (isHovered
                                        ? (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.10))
                                        : Color.clear)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.target)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
            .animation(.spring(response: 0.28, dampingFraction: 0.80), value: isMenuOpen)
            .onHover { isHovered in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    hover.hoveredId = isHovered ? tweet.id : nil
                }
            }
            .help(loc.t("more_actions"))
        }
        .frame(width: 24, height: 24)
        .modifier(LocatesFrame(box: frameBox))
    }
}

// MARK: - Global Floating Menu Overlay (Rendered in AppRootView)
struct TweetOptionsMenuOverlay: View {
    @ObservedObject var manager = TweetOptionsMenuManager.shared
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        GeometryReader { windowGeo in
            if let payload = manager.activeMenu {
                // Transparent backdrop to intercept outside clicks
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
        let menuWidth: CGFloat = 210
        let approxMenuHeight: CGFloat = 220
        let anchor = payload.anchorRect
        
        // Smart edge positioning (flips vertically if near the bottom edge)
        let opensUpward = anchor.maxY + approxMenuHeight > containerSize.height - 18
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
                insertion: .scale(scale: 0.85, anchor: opensUpward ? .bottomTrailing : .topTrailing)
                    .combined(with: .opacity),
                removal: .scale(scale: 0.94, anchor: opensUpward ? .bottomTrailing : .topTrailing)
                    .combined(with: .opacity)
            )
        )
    }
}

// MARK: - Floating Menu Content View (HIG Context Menu Structure)
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
        VStack(alignment: .leading, spacing: 2) {
            // Group 1: Post Actions
            
            // 1. Bookmark
            menuRow(
                title: loc.t(tweet.isBookmarked ? "remove_bookmark" : "bookmark"),
                icon: tweet.isBookmarked ? "bookmark.fill" : "bookmark",
                iconColor: tweet.isBookmarked ? ThemeManager.accent : (theme.isLight ? ThemeManager.primaryText.opacity(0.85) : .white.opacity(0.90)),
                isDestructive: false
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
                iconColor: theme.isLight ? ThemeManager.primaryText.opacity(0.85) : .white.opacity(0.90),
                isDestructive: false
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
                iconColor: theme.isLight ? ThemeManager.primaryText.opacity(0.85) : .white.opacity(0.90),
                isDestructive: false
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
                iconColor: theme.isLight ? ThemeManager.primaryText.opacity(0.85) : .white.opacity(0.90),
                isDestructive: false
            ) {
                onDismiss()
                if let url = URL(string: "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            // 5. Open in Videos: X's video feed, starting with this one
            if tweet.feedVideo != nil {
                menuRow(
                    title: loc.t("open_in_videos"),
                    icon: AppTab.videos.iconName,
                    iconColor: theme.isLight ? ThemeManager.primaryText.opacity(0.85) : .white.opacity(0.90),
                    isDestructive: false
                ) {
                    onDismiss()
                    NavigationManager.shared.openInVideos(tweet)
                }
            }
            
            // Group 2 for your own posts: deleting, last and in red as destructive actions are
            if isSelf {
                Rectangle()
                    .fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                
                // Copies the words first, so the post can be written again, corrected, after it is gone
                menuRow(
                    title: loc.t("post_menu_copy_delete"),
                    icon: "doc.on.doc",
                    iconColor: Color(hex: "#F91880"),
                    isDestructive: true
                ) {
                    onDismiss()
                    PostDeletion.confirm(tweet, copyingText: true)
                }
                
                menuRow(
                    title: loc.t("post_menu_delete"),
                    icon: "trash",
                    iconColor: Color(hex: "#F91880"),
                    isDestructive: true
                ) {
                    onDismiss()
                    PostDeletion.confirm(tweet, copyingText: false)
                }
            }
            
            // Group 2: Author Actions (Flattened directly into menu without awkward submenus)
            if !isSelf {
                // Subtle standard HIG hairline separator
                Rectangle()
                    .fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                
                // 5. Mute @handle
                menuRow(
                    title: loc.format("post_menu_mute", ["handle": tweet.author.formattedHandle]),
                    icon: "speaker.slash",
                    iconColor: Color(hex: "#FF8A00"),
                    isDestructive: false
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
                
                // 6. Block @handle (Destructive action as per Apple HIG)
                menuRow(
                    title: loc.format("post_menu_block", ["handle": tweet.author.formattedHandle]),
                    icon: "nosign",
                    iconColor: Color(hex: "#F91880"),
                    isDestructive: true
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
        .padding(5)
        .background {
            FloatingMenuBackground()
        }
    }
    
    private func menuRow(
        title: String,
        icon: String,
        iconColor: Color,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        MenuRowButton(
            title: title,
            icon: icon,
            iconColor: iconColor,
            isDestructive: isDestructive,
            action: action
        )
    }
}

// MARK: - Deleting Your Own Post

enum PostDeletion {
    /// Asks before deleting, as nothing brings a deleted post back. With `copyingText`, the post's words go to the
    /// clipboard once the deletion is confirmed, so cancelling leaves the clipboard as it was.
    static func confirm(_ tweet: Tweet, copyingText: Bool) {
        let loc = LocalizationManager.shared
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = loc.t("delete_post_title")
        alert.informativeText = loc.t(copyingText ? "copy_delete_post_message" : "delete_post_message")
        let deleteButton = alert.addButton(withTitle: loc.t("delete_action"))
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: loc.t("cancel"))

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            if copyingText {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tweet.copyableText, forType: .string)
            }
            delete(tweet, copiedText: copyingText)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private static func delete(_ tweet: Tweet, copiedText: Bool) {
        let loc = LocalizationManager.shared
        // The original, so deleting your post from a repost of it still deletes the post itself
        let postId = tweet.canonicalId
        APIClient.shared.deleteTweet(id: postId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    TimelineViewModel.shared.removePost(id: postId)
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    AppToastManager.shared.show(loc.t(copiedText ? "post_copied_deleted" : "post_deleted"), icon: "trash")
                case .failure(let error):
                    AppToastManager.shared.show(error.localizedDescription, icon: "xmark.circle")
                }
            }
        }
    }
}

// MARK: - Floating Menu Glass (shared by the post menu and the message menu)

/// Adaptive translucent frosted glass, or Liquid Glass on macOS 26, behind a floating menu card.
struct FloatingMenuBackground: View {
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                shape
                    .fill(Color.clear)
                    .modifier(AdaptiveGlassModifier(isLiquid: true, shape: shape, isClear: true))
            } else {
                frostedGlass(shape: shape)
            }
        } else {
            frostedGlass(shape: shape)
        }
    }
    
    private func frostedGlass(shape: RoundedRectangle) -> some View {
        ZStack {
            // Official Apple system backdrop material: applies real-time Gaussian blur and vibrancy to underlying content
            shape.fill(.ultraThinMaterial)
            
            // Translucent tint allowing underlying timeline posts, text and media to bleed through
            shape.fill(
                theme.isLight
                    ? Color.white.opacity(0.32)
                    : Color(hex: "#18191E").opacity(0.38)
            )
        }
        .clipShape(shape)
        .overlay(
            shape.stroke(
                theme.isLight
                    ? Color.white.opacity(0.75)
                    : Color.white.opacity(0.18),
                lineWidth: 0.75
            )
        )
        .shadow(
            color: Color.black.opacity(theme.isLight ? 0.12 : 0.40),
            radius: 20,
            x: 0,
            y: 10
        )
    }
}

// MARK: - Menu Row Button (Apple HIG Selection & Metrics)
final class RowHoverState: ObservableObject {
    @Published var isHovered = false
}

struct MenuRowButton: View {
    let title: String
    let icon: String
    let iconColor: Color
    let isDestructive: Bool
    let action: () -> Void
    
    @ObservedObject var theme = ThemeManager.shared
    @StateObject private var hover = RowHoverState()
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(isDestructive ? Color(hex: "#F91880") : iconColor)
                    .frame(width: 20, alignment: .center)
                
                Text(title)
                    .font(theme.appFont(size: 13, weight: .regular))
                    .foregroundColor(
                        isDestructive
                            ? Color(hex: "#F91880")
                            : (theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                    )
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        hover.isHovered
                            ? (isDestructive
                                ? Color(hex: "#F91880").opacity(theme.isLight ? 0.10 : 0.15)
                                : (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12)))
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.target)
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: hover.isHovered)
        .onHover { isHovered in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                hover.isHovered = isHovered
            }
        }
    }
}
