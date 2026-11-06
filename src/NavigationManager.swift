//
//  NavigationManager.swift
//  Tweetintosh - Headless Data-driven Client
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

// A full-pane page shown over the tabs
enum OverlayPage {
    case tweet(Tweet)
    case profile(TweetUser)
    case search(String)
    // The people who liked or reposted a post
    case users(TweetUsersKind, tweetId: String)
    // An X Article, read on its own page (the post carries its title and cover)
    case article(Tweet)
}

struct OverlayEntry: Identifiable {
    let id = UUID()
    let page: OverlayPage
}

final class NavigationManager: ObservableObject {
    static let shared = NavigationManager()
    
    @Published var currentTab: AppTab = .home
    @Published var sidebarExpanded: Bool = false {
        didSet {
            if !isContactListFolded { isContactListPeeking = false }
            // The sidebar and the top bar each have their own search field, and only one was focused
            if sidebarExpanded != oldValue { isSearchActive = false }
        }
    }
    @Published var isSearchActive: Bool = false
    @Published var searchQuery: String = ""
    // Full-pane pages pushed over the tabs (tweet detail, profiles), newest last. Each entry keeps its own
    // identity so a page's state survives while others are pushed on top of it.
    @Published private(set) var overlayStack: [OverlayEntry] = []

    var selectedTweetDetail: Tweet? {
        if case .tweet(let tweet) = overlayStack.last?.page { return tweet }
        return nil
    }

    var hasOverlay: Bool { !overlayStack.isEmpty }
    @Published var isShowingCompose: Bool = false
    @Published var composeQuotedTweet: Tweet? = nil
    
    // Back to a clean Home page, as after launching: used when the active account changes
    func resetForAccountChange() {
        overlayStack = []
        DetailPane.shared.clear()
        currentTab = .home
        isShowingCompose = false
        composeQuotedTweet = nil
        replyTargetTweet = nil
        isSearchActive = false
        searchQuery = ""
    }
    
    func openComposer(quoting tweet: Tweet? = nil) {
        if let tweet = tweet, !EngagementGuard.allows(tweet) { return }
        DispatchQueue.main.async {
            self.composeQuotedTweet = tweet
            self.isShowingCompose = true
        }
    }
    
    // Single app-level reply sheet, so timeline rows don't each carry their own .sheet
    @Published var replyTargetTweet: Tweet? = nil
    // Set by the sheet itself, because a post page opens its own reply sheet without going through replyTargetTweet
    var isReplyComposerOpen = false

    func openReply(to tweet: Tweet) {
        guard EngagementGuard.allows(tweet) else { return }
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
    
    func openTweetDetail(_ tweet: Tweet, fromPane: Bool = false) {
        guard !PeekCoordinator.shared.suppressesActivation else { return }
        if DetailPane.shared.isAvailable && currentTab == .home && !hasOverlay {
            DetailPane.shared.open(tweet, fromPane: fromPane)
        } else {
            push(.tweet(tweet))
        }
    }
    
    // The profile page, when it is the page in front
    func activeProfilePage() -> ProfileViewModel? {
        if case .profile? = overlayStack.last?.page { return ProfileViewModel.live.last }
        return nil
    }
    
    // The search results page, when it is the page in front
    func activeSearchPage() -> SearchViewModel? {
        if case .search? = overlayStack.last?.page { return SearchViewModel.current }
        return nil
    }
    
    func openSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SearchRecents.shared.add(trimmed)
        push(.search(trimmed))
    }
    
    func openArticle(for tweet: Tweet) {
        guard tweet.linksToArticle, !PeekCoordinator.shared.suppressesActivation else { return }
        push(.article(tweet))
    }
    
    func openUserList(_ kind: TweetUsersKind, tweetId: String) {
        guard !PeekCoordinator.shared.suppressesActivation else { return }
        push(.users(kind, tweetId: tweetId))
    }
    
    func openProfile(_ user: TweetUser) {
        guard !PeekCoordinator.shared.suppressesActivation else { return }
        // Clicking the author on their own profile page shouldn't stack the same page again
        if case .profile(let current) = overlayStack.last?.page, current.screenName == user.screenName { return }
        push(.profile(user))
    }
    
    // Goes back one page
    func dismissTweetDetail() {
        DispatchQueue.main.async {
            guard !self.overlayStack.isEmpty else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                _ = self.overlayStack.removeLast()
            }
        }
    }
    
    private func push(_ page: OverlayPage) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                self.overlayStack.append(OverlayEntry(page: page))
            }
        }
    }
    
    // MARK: Layout by window width
    
    // The contact list on the Messages page gives way in a narrow window, and can be slid over the chat for a moment
    @Published private var isTooNarrowForContactList = false
    @Published var isContactListPeeking = false
    @Published private var isWideWindow: Bool?
    
    // The sidebar and the contact list only sit side by side past half the screen, so opening the sidebar by hand in a
    // narrower window folds the list for as long as it is open
    var isContactListFolded: Bool {
        isTooNarrowForContactList || (sidebarExpanded && isWideWindow == false)
    }
    
    // Acts only when the window crosses a line, so a sidebar opened or closed by hand stays that way until the next
    // crossing. Wide means clearly past half the screen: a window tiled to half doesn't have the room for the sidebar and
    // the contact list together, and macOS can make it slightly wider than half, so the line sits at 51%. Both lines are
    // shares of the screen the window is on, so they hold on any display.
    func updateLayout(windowWidth: CGFloat, screenWidth: CGFloat) {
        // Open posts move with the layout: to full pages when the pane goes away, and into the pane when it arrives, or
        // a post open as a full page would hide the three columns. Anything else on the stack stays a full page.
        if DetailPane.shared.updateAvailability(windowWidth: windowWidth, screenWidth: screenWidth), currentTab == .home {
            if DetailPane.shared.isAvailable {
                let tweets = overlayStack.compactMap { entry -> Tweet? in
                    if case .tweet(let tweet) = entry.page { return tweet }
                    return nil
                }
                if tweets.count == overlayStack.count && !tweets.isEmpty {
                    DetailPane.shared.adopt(tweets)
                    overlayStack = []
                }
            } else {
                overlayStack.append(contentsOf: DetailPane.shared.takeStack().map { OverlayEntry(page: .tweet($0)) })
            }
        }
        let isWide = windowWidth >= screenWidth * 0.51
        let isFolded = windowWidth < (screenWidth * 2 / 5).rounded(.down)
        guard isWide != isWideWindow || isFolded != isTooNarrowForContactList else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            if isWide != isWideWindow {
                isWideWindow = isWide
                sidebarExpanded = isWide
            }
            isTooNarrowForContactList = isFolded
            if !isContactListFolded { isContactListPeeking = false }
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
    // When Return was last pressed with the keyboard free, for the double-press that opens the composer
    private var lastReturnPress: CFTimeInterval = 0
    private static let doubleReturnInterval: CFTimeInterval = 0.4
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
    
    // Arriving from outside the window: the tab has to end up on screen, so any page open over it closes
    func showTab(_ tab: AppTab) {
        overlayStack = []
        selectTab(tab)
    }
    
    func showSearch() {
        overlayStack = []
        if !isSearchActive { toggleSearch() }
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
                
                // Command + V (keyCode 9) while composing, with an image or media file on the clipboard -> attach it.
                // Anything else on the clipboard (text) pastes as usual.
                if keyCode == 9 && hasCmd && !hasOption && !hasCtrl && (self.isShowingCompose || self.isReplyComposerOpen)
                    && !event.modifierFlags.contains(.shift) && MediaAttachments.hasPastableMedia(.general) {
                    NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_PasteMedia"), object: nil)
                    return nil
                }
                
                // Option + A (keyCode 0) while composing -> Attach media
                if keyCode == 0 && hasOption && !hasCmd && !hasCtrl && (self.isShowingCompose || self.isReplyComposerOpen) {
                    NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_AttachMedia"), object: nil)
                    return nil
                }
                
                // If Esc key is pressed
                if keyCode == 53 {
                    // These keep their own Esc: a file picker closes itself, and Esc cancels a Chinese or Japanese word
                    // still being composed
                    if let panel = event.window as? NSSavePanel, panel.isVisible { return event }
                    if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
                    // Handled here because a text field takes Esc before the Cancel button's shortcut can: an empty one
                    // opens the system's word completion list. It also comes first, or Esc would close a post page
                    // underneath the reply box.
                    if self.isReplyComposerOpen {
                        NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_CancelReply"), object: nil)
                        return nil
                    }
                    if self.isShowingCompose {
                        self.dismissComposer()
                        return nil
                    }
                    if self.hasOverlay {
                        self.dismissTweetDetail()
                        return nil
                    }
                    // A profile preview opened from the list closes first, on its own Esc
                    if self.isContactListPeeking && PeekCoordinator.shared.target == nil {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            self.isContactListPeeking = false
                        }
                        return nil
                    }
                    if self.isSearchActive {
                        self.toggleSearch()
                        return nil
                    }
                    if self.currentTab == .home && DetailPane.shared.isOpen {
                        DetailPane.shared.goBack()
                        return nil
                    }
                }
                
                // Left Arrow (keyCode 123) without modifiers -> Back from Tweet Detail
                if !hasCmd && !hasOption && !hasCtrl && keyCode == 123 {
                    if self.hasOverlay && !self.isShowingCompose && !LightboxManager.shared.isPresented && !VideoLightboxManager.shared.isPresented {
                        if !self.isTextInputActive() {
                            self.dismissTweetDetail()
                            return nil
                        }
                    }
                }
                
                // Up / Down Arrow (keyCodes 126 / 125) without modifiers -> Scroll Home Timeline
                if !hasCmd && !hasOption && !hasCtrl && (keyCode == 126 || keyCode == 125) {
                    if self.currentTab == .home && !self.hasOverlay && !self.isShowingCompose
                        && self.replyTargetTweet == nil && !VideoLightboxManager.shared.isPresented
                        && event.window === NSApp.mainWindow && event.window?.attachedSheet == nil
                        && !self.isTextInputActive() {
                        TimelineScrollCoordinator.shared.arrowKeyDown(up: keyCode == 126, isRepeat: event.isARepeat)
                        return nil
                    }
                }

                // Return pressed twice in quick succession (keyCodes 36 / 76) -> Global New Post Compose.
                // Only when nothing is being typed and no page, sheet or lightbox has taken the keyboard, so Return
                // keeps its usual job in text fields and dialogs.
                if (keyCode == 36 || keyCode == 76) && !hasCmd && !hasOption && !hasCtrl && !event.isARepeat {
                    let canCompose = !self.isShowingCompose && self.replyTargetTweet == nil
                        && !VideoLightboxManager.shared.isPresented
                        && event.window === NSApp.mainWindow && event.window?.attachedSheet == nil
                        && !self.isTextInputActive()
                    let now = CACurrentMediaTime()
                    if canCompose && now - self.lastReturnPress < Self.doubleReturnInterval {
                        self.lastReturnPress = 0
                        self.openComposer()
                        return nil
                    }
                    self.lastReturnPress = canCompose ? now : 0
                    // The first press is the first half of the double press: swallow it, or macOS beeps at a Return
                    // that nothing handles
                    if canCompose { return nil }
                }
                
                // Command + [ (keyCode 33) -> Back from Tweet Detail
                if hasCmd && !hasOption && !hasCtrl && keyCode == 33 {
                    if self.hasOverlay {
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
                    if (keyCode == 123 || keyCode == 124), let search = self.activeSearchPage() {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { search.stepTab(keyCode == 123 ? -1 : 1) }
                        return nil
                    }
                    if (keyCode == 123 || keyCode == 124), let profile = self.activeProfilePage() {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { profile.stepTab(keyCode == 123 ? -1 : 1) }
                        return nil
                    }
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
                
                // Profile page: Option + 1, 2, 3 -> Posts, Media, Replies (the first menu on that page)
                if hasOption && !hasCmd && !hasCtrl, let tab = ProfileTab.forKeyCode(keyCode),
                   let profile = self.activeProfilePage() {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { profile.select(tab) }
                    return nil
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
                
                // Search page: Option + Q, W, E -> Top, Latest, People (same keys as the Notifications filters)
                if hasOption && !hasCmd && !hasCtrl, let tab = SearchTab.forKeyCode(keyCode),
                   let search = self.activeSearchPage() {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { search.select(tab) }
                    return nil
                }
                
                // Secondary Filter Direct Shortcuts: Option + Q, W, E (strictly Option, NOT Cmd to preserve Cmd+Q quit)
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
                    case 13: // Key W -> Home: Following; Notifications: Priority
                        if self.currentTab == .home {
                            TimelineViewModel.shared.selectFeed(.following)
                            return nil
                        } else if self.currentTab == .notifications {
                            NotificationsViewModel.shared.selectFilter(.priority)
                            return nil
                        }
                    case 14: // Key E -> Home: List; Notifications: Mentions
                        if self.currentTab == .home {
                            if !TimelineViewModel.shared.userLists.isEmpty {
                                TimelineViewModel.shared.selectFeed(.list)
                            }
                            return nil
                        } else if self.currentTab == .notifications {
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
