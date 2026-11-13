//
//  main.swift
//  Tweetintosh - Headless Data-driven Client
//

import Cocoa
import SwiftUI
import Combine
import WebKit

// SwiftUI's NSHostingView.acceptsFirstResponder walks the whole focus/responder tree on every call, and AppKit
// asks for it on every frame while content scrolls under the transparent titlebar (window drag-region updates).
// Cache the answer briefly: what is focusable changes rarely compared with that per-frame query rate.
final class FocusCachingHostingView<Content: View>: NSHostingView<Content> {
    private var cachedAcceptsFirstResponder: Bool?
    private var cachedAt: CFTimeInterval = 0

    override var acceptsFirstResponder: Bool {
        let now = CACurrentMediaTime()
        if let cached = cachedAcceptsFirstResponder, now - cachedAt < 0.5 {
            return cached
        }
        let value = super.acceptsFirstResponder
        cachedAcceptsFirstResponder = value
        cachedAt = now
        return value
    }
    
    // System Look Up (three-finger tap, or Force Click when Look Up is set to it) opens the peek card
    override func quickLook(with event: NSEvent) {
        if !PeekCoordinator.shared.quickLook(with: event) {
            super.quickLook(with: event)
        }
    }
}

private final class MainWindow: NSWindow {
    private var frameBeforeTitlebarFill: NSRect?

    override func sendEvent(_ event: NSEvent) {
        if handleTitlebarDoubleClick(event) { return }
        super.sendEvent(event)
    }

    private func handleTitlebarDoubleClick(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, event.clickCount == 2, event.window === self,
              !styleMask.contains(.fullScreen), attachedSheet == nil,
              let screen = screen else { return false }

        let point = event.locationInWindow
        guard point.x >= 0, point.x < frame.width,
              point.y >= contentLayoutRect.maxY, point.y < frame.height,
              !hitsWindowButton(.closeButton, at: point),
              !hitsWindowButton(.miniaturizeButton, at: point),
              !hitsWindowButton(.zoomButton, at: point) else { return false }

        // A custom transparent title bar can route clicks through the hosting view instead of AppKit's title bar.
        let area = screen.visibleFrame
        let target: NSRect
        if frame == area, let previous = frameBeforeTitlebarFill {
            target = previous
            frameBeforeTitlebarFill = nil
        } else {
            frameBeforeTitlebarFill = frame
            target = area
        }
        setFrame(target, display: true, animate: true)
        return true
    }

    private func hitsWindowButton(_ type: NSWindow.ButtonType, at point: NSPoint) -> Bool {
        guard let button = standardWindowButton(type), !button.isHiddenOrHasHiddenAncestor else { return false }
        return button.convert(button.bounds, to: nil).contains(point)
    }
}

// The app used to be called MaX (bundle id com.antigravity.max). On first launch under the new identity, bring
// over its saved settings and its data folder (login credentials and caches) so nothing has to be set up again.
enum LegacyMigration {
    static func run() {
        let defaults = UserDefaults.standard
        let marker = "Tweetintosh_MigratedFromMaX_v2"
        if !defaults.bool(forKey: marker) {
            // Settings saved under the old bundle id, and under old key names in the current one
            let ownDomain = Bundle.main.bundleIdentifier ?? "com.anno.tweetintosh"
            for domain in ["com.antigravity.max", ownDomain] {
                for (key, value) in defaults.persistentDomain(forName: domain) ?? [:] {
                    guard key.hasPrefix("MaX") || key.contains("MaXMainWindow") else { continue }
                    let renamed = key
                        .replacingOccurrences(of: "MaX_", with: "Tweetintosh_")
                        .replacingOccurrences(of: "MaXMainWindow_v2", with: "TweetintoshMainWindow")
                    if defaults.object(forKey: renamed) == nil { defaults.set(value, forKey: renamed) }
                    if domain == ownDomain { defaults.removeObject(forKey: key) }
                }
            }
            defaults.set(true, forKey: marker)
        }
        
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = support.appendingPathComponent("MaX", isDirectory: true)
            let new = support.appendingPathComponent("Tweetintosh", isDirectory: true)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
            }
        }
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static func main() {
        LegacyMigration.run()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    var mainWindow: NSWindow?
    var settingsWindow: NSWindow?
    private var aboutWindow: AboutWindow?
    private var tilingMonitor: Any?
    private var settingsTitleObserver: AnyCancellable?
    private var menuLanguageObserver: AnyCancellable?
    // Shows the Videos menu items only while the Videos tab is turned on in Settings
    private var videosMenuObserver: AnyCancellable?
    // Keeps the Tweetintosh menu's accounts in step with the signed-in accounts
    var accountMenuObserver: AnyCancellable?
    private var sidebarObserver: AnyCancellable?
    var loginController: LoginWindowController?
    private var welcomeController: WelcomeWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        ScrollInput.shared.start()
        // Before the menu, which shows Check for Updates… only when updates can be checked
        UpdateManager.shared.start()
        setupMainMenu()
        menuLanguageObserver = LocalizationManager.shared.$currentLanguage
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupMainMenu()
                self?.aboutWindow?.title = LocalizationManager.shared.t("menu_about")
            }
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceDidChange), name: NSNotification.Name("Tweetintosh_AppearanceDidChange"), object: nil)
        if EULA.needsAcceptance {
            showWelcome()
        } else {
            startApp()
        }
    }
    
    // Nothing is loaded or sent to X until the License Agreement is accepted: the main window creates the timeline,
    // which fetches as soon as it exists
    private func showWelcome() {
        welcomeController = WelcomeWindowController { [weak self] in
            guard let self = self else { return }
            self.welcomeController = nil
            self.startApp()
            // A first launch goes straight on to signing in. After an agreement update there is usually an account
            // already, and then nothing more is asked.
            if CredentialsManager.shared.loadCredentials() == nil {
                DispatchQueue.main.async { self.startLoginFlow() }
            }
        }
        welcomeController?.show()
    }
    
    private func startApp() {
        setupMainWindow()
        AccountManager.shared.refreshActiveInfo()
    }
    
    @objc private func appearanceDidChange() {
        let bg = ThemeManager.windowBackgroundColor
        mainWindow?.backgroundColor = bg
        settingsWindow?.backgroundColor = bg
        aboutWindow?.backgroundColor = bg
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let welcome = welcomeController {
            welcome.show()
            return true
        }
        if !flag {
            if let window = mainWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                setupMainWindow()
            }
        }
        return true
    }
    
    // MARK: - Setup Main Window
    private func setupMainWindow() {
        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let initialRect = NSRect(x: 0, y: 0, width: 720, height: 880)
        let window = MainWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Tweetintosh"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ThemeManager.windowBackgroundColor
        WindowDragging.keepUpdated(window)
        applyMinimumSize(to: window)
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Reopen where the window was last left; centring unconditionally would undo the restored frame, so only a
        // first launch, with nothing saved yet, is centred.
        let restoredFrame = window.setFrameUsingName("TweetintoshMainWindow")
        window.setFrameAutosaveName("TweetintoshMainWindow")
        if !restoredFrame {
            window.center()
        }
        applyMinimumSize(to: window)
        updateLayout(for: window)
        // Opening the sidebar in a narrow window widens the window to fit it, rather than squeezing the page beside it.
        var lastSidebarExpanded = NavigationManager.shared.sidebarExpanded
        sidebarObserver = observeChanges(of: { _ = NavigationManager.shared.sidebarExpanded }) { [weak self, weak window] in
            let expanded = NavigationManager.shared.sidebarExpanded
            guard expanded != lastSidebarExpanded, let self = self, let window = window else { return }
            lastSidebarExpanded = expanded
            self.applyMinimumSize(to: window, sidebarExpanded: expanded, animate: true)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self, weak window] _ in
            if let window = window {
                self?.applyMinimumSize(to: window)
                self?.updateLayout(for: window)
            }
        }
        
        let rootView = AppRootView(
            onOpenSettings: { [weak self] in
                self?.showSettings()
            },
            onLoginRequest: { [weak self] in
                self?.startLoginFlow()
            }
        )
        
        let hostingView = FocusCachingHostingView(rootView: rootView)
        hostingView.frame = window.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        
        window.contentView?.addSubview(hostingView)
        PeekCoordinator.shared.start(hostingView: hostingView)
        // Let AppKit build the Tab key order when it is needed. Otherwise SwiftUI rebuilds it eagerly whenever the
        // set of buttons changes, which in a List walks every table row each time a new row scrolls into view.
        window.autorecalculatesKeyViewLoop = true
        DebugSupport.openBusyReplyPostAfterLaunch()
        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }
    
    // Tears the main window down for real and opens a fresh one. Merely closing it only hides it (see
    // windowShouldClose), and a hidden window's timeline stays alive: it shares the same view model, keeps
    // re-registering its own invisible scroll view with the pull-to-refresh coordinator, and so takes pull-to-refresh
    // away from the visible one.
    private func replaceMainWindow(then afterwards: (() -> Void)? = nil) {
        let old = mainWindow
        mainWindow = nil          // no longer the main window, so windowShouldClose lets it close
        old?.contentView = nil    // drops the SwiftUI tree now, so its onDisappear runs before the new page appears
        old?.close()
        DispatchQueue.main.async { [weak self] in
            self?.setupMainWindow()
            afterwards?()
        }
    }
    
    // MARK: - Accounts
    
    // Everything on screen belongs to the account that was active: empty it, open the window afresh and load the
    // active account's timeline and notifications
    private func reloadForActiveAccount() {
        TimelineViewModel.shared.resetForSignOut()
        NotificationsViewModel.shared.resetForSignOut()
        DMViewModel.shared.reloadForActiveAccount()
        NavigationManager.shared.resetForAccountChange()
        replaceMainWindow {
            TimelineViewModel.shared.signedIn()
            NotificationsViewModel.shared.signedIn()
            AccountManager.shared.refreshActiveInfo()
        }
    }
    
    func switchAccount(to id: String) {
        guard id != AccountManager.shared.activeId else { return }
        AccountManager.shared.setActive(id)
        reloadForActiveAccount()
    }
    
    private func signOutActiveAccount() {
        TimelineCacheManager.shared.clearCache()
        NotificationCacheManager.shared.clearCache()
        DMCacheManager.shared.clearCache()
        MediaCacheManager.shared.clearAllCache()
        let next = AccountManager.shared.removeActive()
        if next != nil {
            // Another account is signed in: carry on as that one
            reloadForActiveAccount()
            return
        }
        settingsWindow?.close()
        TimelineViewModel.shared.resetForSignOut()
        NotificationsViewModel.shared.resetForSignOut()
        DMViewModel.shared.reloadForActiveAccount()
        NavigationManager.shared.resetForAccountChange()
        // The login page signs in by itself when it finds X's cookies, so they have to go too
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            DispatchQueue.main.async { [weak self] in self?.replaceMainWindow() }
        }
    }
    
    // The window stays at least a third of its screen wide, so it follows the screen it is on. A window saved narrower,
    // or moved over from a smaller display, grows to fit rather than waiting to be resized.
    // The narrowest page that still fits a profile's banner: the photo and name on one side, and the following and
    // follower counts on the other without wrapping
    private static let minimumPageWidth: CGFloat = 520

    private func applyMinimumSize(to window: NSWindow, sidebarExpanded: Bool? = nil, animate: Bool = false) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        var minWidth = max(500, (screen.frame.width / 3).rounded(.up))
        if sidebarExpanded ?? NavigationManager.shared.sidebarExpanded {
            minWidth = max(minWidth, SidebarLayout.columnWidth + Self.minimumPageWidth)
        }
        minWidth = min(minWidth, screen.visibleFrame.width)
        window.minSize = NSSize(width: minWidth, height: 600)
        guard window.frame.width < minWidth else { return }
        // Grows to the right, unless that would leave the screen
        var frame = window.frame
        frame.size.width = minWidth
        frame.origin.x = min(frame.origin.x, screen.visibleFrame.maxX - minWidth)
        window.setFrame(frame, display: true, animate: animate)
    }
    
    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        applyMinimumSize(to: window)
        updateLayout(for: window)
    }
    
    // The size a full-screen transition ends at can arrive only with the end of the transition
    func windowDidEnterFullScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mainWindow { updateLayout(for: window) }
    }
    
    func windowDidExitFullScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mainWindow { updateLayout(for: window) }
    }
    
    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mainWindow { updateLayout(for: window) }
    }
    
    private func updateLayout(for window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        NavigationManager.shared.updateLayout(windowWidth: window.frame.width, screenWidth: screen.frame.width)
    }
    
    // MARK: - NSWindowDelegate (Prevent Deallocation on Close)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == mainWindow {
            sender.orderOut(nil)
            return false // Keeps window in memory so Dock click brings it back instantly
        }
        return true
    }
    
    // MARK: - Login Flow
    func startLoginFlow() {
        loginController = LoginWindowController { [weak self] creds in
            guard let self = self else { return }
            self.loginController = nil
            guard let creds = creds else { return }
            // Ask X who just signed in, add them to the accounts and switch to them
            AccountManager.fetchInfo(for: creds) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let info):
                        AccountManager.shared.addOrUpdate(creds: creds, info: info)
                        self.reloadForActiveAccount()
                    case .failure:
                        let alert = NSAlert()
                        alert.messageText = "Couldn't read the account that signed in"
                        alert.informativeText = "X didn't answer. Check the connection and try adding the account again."
                        alert.runModal()
                    }
                }
            }
        }
        loginController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Dock Menu
    // The app's items above what macOS adds itself (Options, Show All Windows, Hide, Quit). Built each time the menu
    // opens, so it follows the current language.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let loc = LocalizationManager.shared
        let menu = NSMenu()
        let items: [(key: String, action: Selector)] = [
            ("new_post", #selector(dockNewPost)),
            ("tab_search", #selector(dockSearch)),
            ("tab_notifications", #selector(dockNotifications)),
            ("tab_messages", #selector(dockMessages))
        ]
        for item in items {
            let menuItem = NSMenuItem(title: loc.t(item.key), action: item.action, keyEquivalent: "")
            menuItem.target = self
            menu.addItem(menuItem)
        }
        return menu
    }
    
    // A Dock menu is used while the app is in the background, or with its window closed
    private func bringMainWindowForward() {
        // Before the License Agreement is accepted the only window is the welcome window
        if let welcome = welcomeController {
            welcome.show()
            return
        }
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            setupMainWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func dockNewPost() {
        bringMainWindowForward()
        NavigationManager.shared.openComposer()
    }
    @objc private func dockSearch() {
        bringMainWindowForward()
        NavigationManager.shared.showSearch()
    }
    @objc private func dockNotifications() {
        bringMainWindowForward()
        NavigationManager.shared.showTab(.notifications)
    }
    @objc private func dockMessages() {
        bringMainWindowForward()
        NavigationManager.shared.showTab(.messages)
    }
    
    // MARK: - Navigation Menu Actions
    @objc func selectHome() {
        NavigationManager.shared.selectTab(.home)
    }
    @objc func selectNotifications() {
        NavigationManager.shared.selectTab(.notifications)
    }
    @objc func selectMessages() {
        NavigationManager.shared.selectTab(.messages)
    }
    @objc func selectVideos() {
        NavigationManager.shared.selectTab(.videos)
    }
    @objc func videosTogglePlayback() {
        VideosFeed.shared.togglePlayback()
    }
    @objc func videosNext() {
        VideosFeed.shared.move(by: 1)
    }
    @objc func videosPrevious() {
        VideosFeed.shared.move(by: -1)
    }
    @objc func videosToggleMute() {
        VideosFeed.shared.isMuted.toggle()
    }
    @objc func toggleSearchAction() {
        NavigationManager.shared.toggleSearch()
    }
    @objc func focusSearchAction() {
        NavigationManager.shared.focusSearch()
    }

// MARK: - Custom Settings Window (Frameless with Esc Dismiss)
final class SettingsWindow: NSWindow {
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        hideTrafficLights()
    }
    
    override func becomeKey() {
        super.becomeKey()
        hideTrafficLights()
    }
    
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        hideTrafficLights()
    }

    func hideTrafficLights() {
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override func cancelOperation(_ sender: Any?) {
        self.close()
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            self.close()
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            return
        }
        super.keyDown(with: event)
    }
    
    override var canBecomeKey: Bool {
        true
    }
}

    // MARK: - Settings Window (Cmd+,)
    @objc func showSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsRect = NSRect(x: 0, y: 0, width: 480, height: 860)
        let win = SettingsWindow(
            contentRect: settingsRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = LocalizationManager.shared.t("settings")
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        
        // Ensure traffic lights remain completely hidden
        win.hideTrafficLights()
        
        // The title bar is AppKit, so it has to be told when the language changes. @Published announces the change
        // before the new value is stored, hence the hop to the next main-queue turn before reading the title.
        settingsTitleObserver = LocalizationManager.shared.$currentLanguage
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak win] _ in
                win?.title = LocalizationManager.shared.t("settings")
            }
        win.center()
        win.isReleasedWhenClosed = false
        win.backgroundColor = ThemeManager.windowBackgroundColor
        
        let settingsView = SettingsView(
            onSignOut: { [weak self] in
                self?.signOutActiveAccount()
            },
            onSwitchAccount: { [weak self] id in
                self?.switchAccount(to: id)
            },
            onAddAccount: { [weak self] in
                self?.startLoginFlow()
            },
            onClearCache: {
                TimelineCacheManager.shared.clearCache()
                NotificationCacheManager.shared.clearCache()
                MediaCacheManager.shared.clearAllCache()
            },
            onClose: { [weak win, weak self] in
                win?.close()
                self?.mainWindow?.makeKeyAndOrderFront(nil)
            }
        )
        
        let hostingView = NSHostingView(rootView: settingsView)
        // Settings draws its own header across the full window, including the hidden native title bar.
        hostingView.safeAreaRegions = []
        hostingView.frame = win.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(hostingView)
        
        self.settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Native Menu Bar
    private func setupMainMenu() {
        let loc = LocalizationManager.shared
        let mainMenu = NSMenu()
        
        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Tweetintosh")
        appMenu.addItem(withTitle: loc.t("menu_about"), action: #selector(showAbout), keyEquivalent: "")
        addUpdateCommand(to: appMenu)
        appMenu.addItem(NSMenuItem.separator())
        let prefItem = NSMenuItem(title: loc.t("settings") + "…", action: #selector(showSettings), keyEquivalent: ",")
        prefItem.keyEquivalentModifierMask = .command
        appMenu.addItem(prefItem)
        appMenu.addItem(NSMenuItem.separator())
        addAccountCommands(to: appMenu, at: appMenu.items.count)
        appMenu.addItem(withTitle: loc.t("menu_hide_app"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: loc.t("menu_hide_others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: loc.t("menu_show_all"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: loc.t("menu_quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: loc.t("menu_file"))
        fileMenu.addItem(withTitle: loc.t("menu_close_window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addFileCommands(to: fileMenu)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: loc.t("menu_edit"))
        editMenu.addItem(withTitle: loc.t("menu_undo"), action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: loc.t("menu_redo"), action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: loc.t("menu_cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: loc.t("menu_copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: loc.t("menu_paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: loc.t("menu_select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        // ⌘F is where a Mac user looks for search, whatever the app calls it
        let findItem = NSMenuItem(title: loc.t("menu_search"), action: #selector(focusSearchAction), keyEquivalent: "f")
        findItem.keyEquivalentModifierMask = .command
        findItem.target = self
        editMenu.addItem(findItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: loc.t("menu_view"))
        let reloadItem = NSMenuItem(title: loc.t("menu_reload_timeline"), action: #selector(reloadTimeline), keyEquivalent: "r")
        reloadItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(reloadItem)
        
        let toggleSidebarItem = NSMenuItem(title: loc.t("menu_toggle_sidebar"), action: #selector(toggleSidebarAction), keyEquivalent: "`")
        toggleSidebarItem.keyEquivalentModifierMask = .option
        toggleSidebarItem.target = self
        viewMenu.addItem(toggleSidebarItem)
        addPaneCommand(to: viewMenu)
        addTextSizeCommands(to: viewMenu)
        
        viewMenu.addItem(NSMenuItem.separator())
        addFeedCommands(to: viewMenu, at: viewMenu.items.count)
        let toggleFullscreen = NSMenuItem(title: loc.t("menu_enter_full_screen"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        toggleFullscreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(toggleFullscreen)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // 5. Navigate Menu (Option + 1/2/3/S)
        let navMenuItem = NSMenuItem()
        let navMenu = NSMenu(title: loc.t("menu_navigate"))
        
        let homeItem = NSMenuItem(title: loc.t("tab_home"), action: #selector(selectHome), keyEquivalent: "1")
        homeItem.keyEquivalentModifierMask = .option
        homeItem.target = self
        navMenu.addItem(homeItem)
        
        let notifItem = NSMenuItem(title: loc.t("tab_notifications"), action: #selector(selectNotifications), keyEquivalent: "2")
        notifItem.keyEquivalentModifierMask = .option
        notifItem.target = self
        navMenu.addItem(notifItem)
        
        let msgItem = NSMenuItem(title: loc.t("tab_messages"), action: #selector(selectMessages), keyEquivalent: "3")
        msgItem.keyEquivalentModifierMask = .option
        msgItem.target = self
        navMenu.addItem(msgItem)
        
        let videosItem = NSMenuItem(title: loc.t("tab_videos"), action: #selector(selectVideos), keyEquivalent: "4")
        videosItem.keyEquivalentModifierMask = .option
        videosItem.target = self
        navMenu.addItem(videosItem)
        
        navMenu.addItem(NSMenuItem.separator())
        
        let searchItem = NSMenuItem(title: loc.t("tab_search"), action: #selector(toggleSearchAction), keyEquivalent: "s")
        searchItem.keyEquivalentModifierMask = .option
        searchItem.target = self
        navMenu.addItem(searchItem)
        addNavigationCommands(to: navMenu)
        
        navMenuItem.submenu = navMenu
        mainMenu.addItem(navMenuItem)
        mainMenu.addItem(makePostMenu())
        
        // 6. Controls Menu: the Videos tab's playback. The keys are handled by NavigationManager's key monitor before
        // the menu sees them; the items are here so the commands can be found, and are enabled only while the Videos tab
        // has the keyboard, so Space and the arrows keep their usual jobs everywhere else.
        let controlsMenuItem = NSMenuItem()
        let controlsMenu = NSMenu(title: loc.t("menu_controls"))
        let playItem = NSMenuItem(title: loc.t("videos_play"), action: #selector(videosTogglePlayback), keyEquivalent: " ")
        playItem.keyEquivalentModifierMask = []
        playItem.target = self
        controlsMenu.addItem(playItem)
        let nextItem = NSMenuItem(title: loc.t("videos_next"), action: #selector(videosNext),
                                  keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        nextItem.keyEquivalentModifierMask = []
        nextItem.target = self
        controlsMenu.addItem(nextItem)
        let previousItem = NSMenuItem(title: loc.t("videos_previous"), action: #selector(videosPrevious),
                                      keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        previousItem.keyEquivalentModifierMask = []
        previousItem.target = self
        controlsMenu.addItem(previousItem)
        controlsMenu.addItem(NSMenuItem.separator())
        let muteItem = NSMenuItem(title: loc.t("videos_mute"), action: #selector(videosToggleMute), keyEquivalent: "")
        muteItem.target = self
        controlsMenu.addItem(muteItem)
        controlsMenuItem.submenu = controlsMenu
        mainMenu.addItem(controlsMenuItem)
        // Without the Videos tab these commands have nothing to act on, so they leave the menu bar altogether. Hidden
        // items' key equivalents stay live, so the actions check the setting too (selectTab, videosOwnKeyboard).
        videosMenuObserver = ThemeManager.shared.$showVideosTab
            .sink { [weak videosItem, weak controlsMenuItem] isShown in
                videosItem?.isHidden = !isShown
                controlsMenuItem?.isHidden = !isShown
            }
        
        // 7. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: loc.t("menu_window"))
        windowMenu.addItem(withTitle: loc.t("menu_minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: loc.t("menu_zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        mainMenu.addItem(makeHelpMenu())
        
        NSApp.mainMenu = mainMenu
        installWindowTilingShortcuts()
        // Registering the Window menu as the app's window menu lets macOS add its "Move & Resize" items to it, which
        // is also what makes the window respond to fn + Control + Left / Right (tile to that half of the screen)
        NSApp.windowsMenu = windowMenu
    }
    
    // fn + Control + Left / Right snaps the window to that half of its screen. macOS does this for apps with a standard
    // Window menu; handling it here too means it also works when the system doesn't deliver it to the app.
    private func installWindowTilingShortcuts() {
        guard tilingMonitor == nil else { return }
        tilingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard (event.keyCode == 123 || event.keyCode == 124),
                  flags.contains(.control), flags.contains(.function),
                  flags.isDisjoint(with: [.command, .option, .shift]),
                  let window = event.window, window.styleMask.contains(.resizable),
                  let screen = window.screen ?? NSScreen.main else { return event }
            let area = screen.visibleFrame
            let half = (area.width / 2).rounded(.down)
            let x = event.keyCode == 123 ? area.minX : area.maxX - half
            window.setFrame(NSRect(x: x, y: area.minY, width: half, height: area.height), display: true, animate: true)
            return nil
        }
    }
    
    @objc func reloadTimeline() {
        NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_RefreshTimeline"), object: nil)
    }
    
    @objc func toggleSidebarAction() {
        NavigationManager.shared.toggleSidebar()
    }
    
    @objc func showAbout() {
        if aboutWindow == nil {
            aboutWindow = AboutWindow(screen: mainWindow?.screen)
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Menu Validation
extension AppDelegate: NSMenuItemValidation {
    // The Controls menu works only on the Videos tab, and its titles say what a press would do now
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let nav = NavigationManager.shared
        let feed = VideosFeed.shared
        let loc = LocalizationManager.shared
        switch menuItem.action {
        case #selector(videosTogglePlayback):
            menuItem.title = loc.t(feed.isPlaying && nav.currentTab == .videos ? "videos_pause" : "videos_play")
            return nav.videosOwnKeyboard
        case #selector(videosNext), #selector(videosPrevious):
            return nav.videosOwnKeyboard
        case #selector(videosToggleMute):
            menuItem.title = loc.t(feed.isMuted ? "videos_unmute" : "videos_mute")
            return nav.currentTab == .videos
        default:
            // The commands in MenuCommands.swift answer for themselves
            return validateCommand(menuItem) ?? true
        }
    }
}
