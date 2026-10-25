//
//  NavigationManager.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit

enum AppTab: Int, CaseIterable, Identifiable {
    case home = 0
    case notifications = 1
    case messages = 2
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .notifications: return "Notifications"
        case .messages: return "Messages"
        }
    }
    
    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .notifications: return "bell.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        }
    }
}

final class NavigationManager: ObservableObject {
    static let shared = NavigationManager()
    
    @Published var currentTab: AppTab = .home
    @Published var sidebarExpanded: Bool = false
    @Published var isSearchActive: Bool = false
    @Published var searchQuery: String = ""
    @Published var selectedTweetDetail: Tweet? = nil
    @Published var isShowingCompose: Bool = false
    @Published var composeQuotedTweet: Tweet? = nil
    
    func openComposer(quoting tweet: Tweet? = nil) {
        DispatchQueue.main.async {
            self.composeQuotedTweet = tweet
            self.isShowingCompose = true
        }
    }
    
    // Single app-level reply sheet, so timeline rows don't each carry their own .sheet
    @Published var replyTargetTweet: Tweet? = nil

    func openReply(to tweet: Tweet) {
        DispatchQueue.main.async {
            self.replyTargetTweet = tweet
        }
    }

    func dismissComposer() {
        DispatchQueue.main.async {
            self.isShowingCompose = false
            self.composeQuotedTweet = nil
        }
    }
    
    func openTweetDetail(_ tweet: Tweet) {
        guard !PeekCoordinator.shared.suppressesActivation else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                self.selectedTweetDetail = tweet
            }
        }
    }
    
    func dismissTweetDetail() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                self.selectedTweetDetail = nil
            }
        }
    }
    
    func toggleSidebar() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                self.sidebarExpanded.toggle()
            }
        }
    }
    
    // Shortcut badges visibility (revealed when holding Command for > 1.5s without any keystroke)
    @Published var showShortcutBadges: Bool = false
    private var cmdHoldTimer: Timer?
    private var isCmdDown: Bool = false
    
    private var eventMonitor: Any?
    
    private init() {
        setupKeyboardMonitoring()
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        cmdHoldTimer?.invalidate()
    }
    
    func selectTab(_ tab: AppTab) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                self.currentTab = tab
                self.isSearchActive = false
            }
        }
    }
    
    func nextTab() {
        let all = AppTab.allCases
        if let idx = all.firstIndex(of: currentTab), idx < all.count - 1 {
            selectTab(all[idx + 1])
        }
    }
    
    func prevTab() {
        let all = AppTab.allCases
        if let idx = all.firstIndex(of: currentTab), idx > 0 {
            selectTab(all[idx - 1])
        }
    }
    
    func toggleSearch() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                if !self.isSearchActive && self.sidebarExpanded {
                    self.sidebarExpanded = false
                }
                self.isSearchActive.toggle()
            }
        }
    }
    
    // MARK: - Global Shortcut & Command Long-Press Engine
    private func setupKeyboardMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self = self else { return event }
            
            // Only handle if main window is active and lightbox is not presented
            guard !LightboxManager.shared.isPresented else {
                self.hideShortcutBadges()
                return event
            }
            
            // 1. Detect Command key hold / release for revealing shortcut hints
            if event.type == .flagsChanged {
                let hasCmd = event.modifierFlags.contains(.command)
                
                if hasCmd && !self.isCmdDown {
                    self.isCmdDown = true
                    self.cmdHoldTimer?.invalidate()
                    // If Command is held for > 1.5s without any keystroke, reveal shortcut badges
                    self.cmdHoldTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        guard let self = self, self.isCmdDown else { return }
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                self.showShortcutBadges = true
                            }
                        }
                    }
                } else if !hasCmd && self.isCmdDown {
                    self.isCmdDown = false
                    self.hideShortcutBadges()
                }
                return event
            }
            
            // 2. Handle KeyDown events
            if event.type == .keyDown {
                // Any keystroke cancels the timer and dismisses shortcut badges immediately
                self.hideShortcutBadges()
                
                let hasOption = event.modifierFlags.contains(.option)
                let hasCmd = event.modifierFlags.contains(.command)
                let hasCtrl = event.modifierFlags.contains(.control)
                let keyCode = event.keyCode
                
                // If Esc key is pressed
                if keyCode == 53 {
                    if self.isShowingCompose {
                        self.dismissComposer()
                        return nil
                    }
                    if self.selectedTweetDetail != nil {
                        self.dismissTweetDetail()
                        return nil
                    }
                    if self.isSearchActive {
                        self.toggleSearch()
                        return nil
                    }
                }
                
                // Left Arrow (keyCode 123) without modifiers -> Back from Tweet Detail
                if !hasCmd && !hasOption && !hasCtrl && keyCode == 123 {
                    if self.selectedTweetDetail != nil && !self.isShowingCompose && !LightboxManager.shared.isPresented && !VideoLightboxManager.shared.isPresented {
                        if !self.isTextInputActive() {
                            self.dismissTweetDetail()
                            return nil
                        }
                    }
                }
                
                // Up / Down Arrow (keyCodes 126 / 125) without modifiers -> Scroll Home Timeline
                if !hasCmd && !hasOption && !hasCtrl && (keyCode == 126 || keyCode == 125) {
                    if self.currentTab == .home && self.selectedTweetDetail == nil && !self.isShowingCompose
                        && self.replyTargetTweet == nil && !VideoLightboxManager.shared.isPresented
                        && event.window === NSApp.mainWindow && event.window?.attachedSheet == nil
                        && !self.isTextInputActive() {
                        TimelineScrollCoordinator.shared.arrowKeyDown(up: keyCode == 126, isRepeat: event.isARepeat)
                        return nil
                    }
                }

                // Command + N (keyCode 45) -> Global New Tweet Compose
                if hasCmd && !hasOption && !hasCtrl && keyCode == 45 {
                    self.openComposer()
                    return nil
                }
                
                // Command + [ (keyCode 33) -> Back from Tweet Detail
                if hasCmd && !hasOption && !hasCtrl && keyCode == 33 {
                    if self.selectedTweetDetail != nil {
                        self.dismissTweetDetail()
                        return nil
                    }
                }
                
                // Option + ` (keyCode 50, key immediately to the left of 1) -> Toggle Sidebar
                if hasOption && !hasCmd && !hasCtrl && keyCode == 50 {
                    self.toggleSidebar()
                    return nil
                }
                
                // Option + Command + Left/Right Arrow -> Secondary Filter Horizontal Navigation
                if hasOption && hasCmd && !hasCtrl {
                    if keyCode == 123 { // Left Arrow
                        if self.currentTab == .home {
                            TimelineViewModel.shared.prevFeed()
                            return nil
                        } else if self.currentTab == .notifications {
                            NotificationsViewModel.shared.prevFilter()
                            return nil
                        }
                    } else if keyCode == 124 { // Right Arrow
                        if self.currentTab == .home {
                            TimelineViewModel.shared.nextFeed()
                            return nil
                        } else if self.currentTab == .notifications {
                            NotificationsViewModel.shared.nextFilter()
                            return nil
                        }
                    }
                }
                
                // Option + Left/Right Arrow -> Primary Tabs Navigation
                if hasOption && !hasCmd && !hasCtrl {
                    if keyCode == 123 { // Left Arrow
                        self.prevTab()
                        return nil
                    } else if keyCode == 124 { // Right Arrow
                        self.nextTab()
                        return nil
                    }
                }
                
                // Option + 1, 2, 3 (or Cmd + 1, 2, 3) -> Primary Tab Switching
                if (hasOption || hasCmd) && !hasCtrl {
                    switch keyCode {
                    case 18: // Key 1 -> Home
                        self.selectTab(.home)
                        return nil
                    case 19: // Key 2 -> Notifications
                        self.selectTab(.notifications)
                        return nil
                    case 20: // Key 3 -> Messages
                        self.selectTab(.messages)
                        return nil
                    default:
                        break
                    }
                }
                
                // Secondary Filter Direct Shortcuts: Option + Q, W, E, R (strictly Option, NOT Cmd to preserve Cmd+Q quit)
                if hasOption && !hasCmd && !hasCtrl {
                    switch keyCode {
                    case 12: // Key Q -> Home: For You; Notifications: All
                        if self.currentTab == .home {
                            TimelineViewModel.shared.selectFeed(.forYou)
                            return nil
                        } else if self.currentTab == .notifications {
                            NotificationsViewModel.shared.selectFilter(.all)
                            return nil
                        }
                    case 13: // Key W -> Home: Following; Notifications: Likes & Reposts
                        if self.currentTab == .home {
                            TimelineViewModel.shared.selectFeed(.following)
                            return nil
                        } else if self.currentTab == .notifications {
                            NotificationsViewModel.shared.selectFilter(.likesAndReposts)
                            return nil
                        }
                    case 14: // Key E -> Home: List; Notifications: Comments
                        if self.currentTab == .home {
                            if !TimelineViewModel.shared.userLists.isEmpty {
                                TimelineViewModel.shared.selectFeed(.list)
                            }
                            return nil
                        } else if self.currentTab == .notifications {
                            NotificationsViewModel.shared.selectFilter(.comments)
                            return nil
                        }
                    case 15: // Key R -> Mentions
                        if self.currentTab == .notifications {
                            NotificationsViewModel.shared.selectFilter(.mentions)
                            return nil
                        }
                    case 1: // Key S -> Toggle Search
                        self.toggleSearch()
                        return nil
                    default:
                        break
                    }
                }
            }
            
            return event
        }
    }
    
    func hideShortcutBadges() {
        cmdHoldTimer?.invalidate()
        cmdHoldTimer = nil
        if showShortcutBadges {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    self.showShortcutBadges = false
                }
            }
        }
    }
    
    private func isTextInputActive() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder ?? NSApp.mainWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView, textView.isEditable {
            return true
        }
        if responder is NSTextField {
            return true
        }
        return false
    }
}
