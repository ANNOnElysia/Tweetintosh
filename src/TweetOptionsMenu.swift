//
//  TweetOptionsMenu.swift
//  Tweetintosh
//
//  Three-dots action menu for posts complying with macOS Human Interface Guidelines (HIG).
//  Provides native context actions: Bookmark, Copy Link, Share, Open in Browser, Mute, Block.
//  Includes smooth spring animations, hover & open transitions, and auto-dismiss on scroll.
//

import SwiftUI
import AppKit

// MARK: - Active Menu Tracker (Auto-dismiss on scroll & seamless continuous scrolling)
final class ActiveMenuTracker: NSObject {
    static let shared = ActiveMenuTracker()
    private weak var currentMenu: NSMenu?
    private var scrollMonitor: Any?
    
    func track(menu: NSMenu) {
        currentMenu = menu
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self = self, let menu = self.currentMenu else { return event }
                // Immediately cancel tracking without animation so scrolling feels instant and uninterrupted
                menu.cancelTrackingWithoutAnimation()
                self.currentMenu = nil
                // Pass the scroll event through to the scroll view hierarchy
                return event
            }
        }
    }
    
    func untrack() {
        currentMenu = nil
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }
}

// MARK: - State
private final class MenuButtonState: ObservableObject {
    @Published var isHovered = false
    @Published var isOpen = false
}

// MARK: - Options Button
struct TweetOptionsMenuButton: View {
    let tweet: Tweet
    var onToggleBookmark: (() -> Void)? = nil
    
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @StateObject private var state = MenuButtonState()
    
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
        Button(action: showMenu) {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(
                    state.isOpen || state.isHovered
                        ? (theme.isLight ? ThemeManager.primaryText : Color.white)
                        : (theme.isLight ? ThemeManager.secondaryText.opacity(0.8) : Color.white.opacity(0.55))
                )
                .rotationEffect(.degrees(state.isOpen ? 90 : 0))
                .scaleEffect(state.isOpen ? 1.05 : (state.isHovered ? 1.10 : 1.0))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            state.isOpen
                                ? (theme.isLight ? Color.black.opacity(0.09) : Color.white.opacity(0.18))
                                : (state.isHovered
                                    ? (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                                    : Color.clear)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.isHovered)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: state.isOpen)
        .onHover { isHovered in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                state.isHovered = isHovered
            }
        }
        .help(loc.t("more_actions"))
    }
    
    private func showMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            state.isOpen = true
        }
        
        let menu = NSMenu()
        let tweet = self.tweet
        let loc = self.loc
        let onToggleBookmark = self.onToggleBookmark
        
        // 1. Bookmark
        menu.addItem(ClosureMenuItem(
            title: loc.t(tweet.isBookmarked ? "remove_bookmark" : "bookmark"),
            symbol: tweet.isBookmarked ? "bookmark.fill" : "bookmark"
        ) {
            let willBookmark = !tweet.isBookmarked
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
        })
        
        // 2. Copy Link
        menu.addItem(ClosureMenuItem(
            title: loc.t("copy_link"),
            symbol: "link"
        ) {
            let url = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            AppToastManager.shared.show(loc.t("link_copied"), icon: "checkmark.circle.fill")
        })
        
        // 3. Share...
        menu.addItem(ClosureMenuItem(
            title: loc.t("share"),
            symbol: "square.and.arrow.up"
        ) {
            let urlStr = "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)"
            if let url = URL(string: urlStr) {
                let picker = NSSharingServicePicker(items: [url])
                if let window = NSApp.keyWindow, let contentView = window.contentView {
                    let mouseLoc = window.mouseLocationOutsideOfEventStream
                    picker.show(relativeTo: NSRect(x: mouseLoc.x, y: mouseLoc.y, width: 1, height: 1), of: contentView, preferredEdge: .minY)
                }
            }
        })
        
        // 4. Open in Browser
        menu.addItem(ClosureMenuItem(
            title: loc.t("open_in_browser"),
            symbol: "safari"
        ) {
            if let url = URL(string: "https://x.com/\(tweet.author.screenName)/status/\(tweet.id)") {
                NSWorkspace.shared.open(url)
            }
        })
        
        // Author moderation actions (Mute & Block) if not authored by self
        if !isSelf {
            menu.addItem(NSMenuItem.separator())
            
            // 5. Mute @handle
            menu.addItem(ClosureMenuItem(
                title: loc.format("post_menu_mute", ["handle": tweet.author.formattedHandle]),
                symbol: "speaker.slash"
            ) {
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
            })
            
            // 6. Block @handle
            menu.addItem(ClosureMenuItem(
                title: loc.format("post_menu_block", ["handle": tweet.author.formattedHandle]),
                symbol: "nosign"
            ) {
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
            })
        }
        
        // Track menu for scroll cancellation
        ActiveMenuTracker.shared.track(menu: menu)
        
        // Pop up the menu anchored at current mouse click
        if let event = NSApp.currentEvent, let window = event.window,
           event.type == .leftMouseUp || event.type == .leftMouseDown {
            menu.popUp(positioning: nil, at: window.convertPoint(toScreen: event.locationInWindow), in: nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        
        ActiveMenuTracker.shared.untrack()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            state.isOpen = false
        }
    }
}
