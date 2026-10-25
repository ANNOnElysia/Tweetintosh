//
//  main.swift
//  MaX - Headless Data-driven Client
//

import Cocoa
import SwiftUI

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
    
    // System Look Up (three-finger tap, or Force Click when Look Up is set to it) opens MaX's peek card
    override func quickLook(with event: NSEvent) {
        if !PeekCoordinator.shared.quickLook(with: event) {
            super.quickLook(with: event)
        }
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    var mainWindow: NSWindow?
    var settingsWindow: NSWindow?
    var loginController: LoginWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMainWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceDidChange), name: NSNotification.Name("MaX_AppearanceDidChange"), object: nil)
    }
    
    @objc private func appearanceDidChange() {
        let bg = ThemeManager.windowBackgroundColor
        mainWindow?.backgroundColor = bg
        settingsWindow?.backgroundColor = bg
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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
        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "MaX"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = ThemeManager.windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 500, height: 600)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("MaXMainWindow_v2")
        window.center()
        
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
        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)
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
    private func startLoginFlow() {
        loginController = LoginWindowController { [weak self] creds in
            guard let self = self else { return }
            if let creds = creds {
                CredentialsManager.shared.saveCredentials(creds)
                self.setupMainWindow()
            }
            self.loginController = nil
        }
        loginController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    @objc func toggleSearchAction() {
        NavigationManager.shared.toggleSearch()
    }

    // MARK: - Settings Window (Cmd+,)
    @objc func showSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsRect = NSRect(x: 0, y: 0, width: 480, height: 660)
        let win = NSWindow(
            contentRect: settingsRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = LocalizationManager.shared.t("settings")
        win.center()
        win.isReleasedWhenClosed = false
        win.backgroundColor = ThemeManager.windowBackgroundColor
        
        let settingsView = SettingsView(
            onSignOut: { [weak self] in
                CredentialsManager.shared.clearCredentials()
                TimelineCacheManager.shared.clearCache()
                NotificationCacheManager.shared.clearCache()
                MediaCacheManager.shared.clearAllCache()
                self?.settingsWindow?.close()
                self?.mainWindow?.close()
                self?.mainWindow = nil
                self?.setupMainWindow()
            },
            onClearCache: {
                TimelineCacheManager.shared.clearCache()
                NotificationCacheManager.shared.clearCache()
                MediaCacheManager.shared.clearAllCache()
            }
        )
        
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = win.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(hostingView)
        
        self.settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Native Menu Bar
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "MaX")
        appMenu.addItem(withTitle: "About MaX", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let prefItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        prefItem.keyEquivalentModifierMask = .command
        appMenu.addItem(prefItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide MaX", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit MaX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let reloadItem = NSMenuItem(title: "Reload Timeline", action: #selector(reloadTimeline), keyEquivalent: "r")
        reloadItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(reloadItem)
        
        let toggleSidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebarAction), keyEquivalent: "`")
        toggleSidebarItem.keyEquivalentModifierMask = .option
        toggleSidebarItem.target = self
        viewMenu.addItem(toggleSidebarItem)
        
        viewMenu.addItem(NSMenuItem.separator())
        let toggleFullscreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        toggleFullscreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(toggleFullscreen)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // 5. Navigate Menu (Option + 1/2/3/S)
        let navMenuItem = NSMenuItem()
        let navMenu = NSMenu(title: "Navigate")
        
        let homeItem = NSMenuItem(title: "Home", action: #selector(selectHome), keyEquivalent: "1")
        homeItem.keyEquivalentModifierMask = .option
        homeItem.target = self
        navMenu.addItem(homeItem)
        
        let notifItem = NSMenuItem(title: "Notifications", action: #selector(selectNotifications), keyEquivalent: "2")
        notifItem.keyEquivalentModifierMask = .option
        notifItem.target = self
        navMenu.addItem(notifItem)
        
        let msgItem = NSMenuItem(title: "Messages", action: #selector(selectMessages), keyEquivalent: "3")
        msgItem.keyEquivalentModifierMask = .option
        msgItem.target = self
        navMenu.addItem(msgItem)
        
        navMenu.addItem(NSMenuItem.separator())
        
        let searchItem = NSMenuItem(title: "Search", action: #selector(toggleSearchAction), keyEquivalent: "s")
        searchItem.keyEquivalentModifierMask = .option
        searchItem.target = self
        navMenu.addItem(searchItem)
        
        navMenuItem.submenu = navMenu
        mainMenu.addItem(navMenuItem)
        
        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    @objc func reloadTimeline() {
        NotificationCenter.default.post(name: NSNotification.Name("MaX_RefreshTimeline"), object: nil)
    }
    
    @objc func toggleSidebarAction() {
        NavigationManager.shared.toggleSidebar()
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MaX v2.0"
        alert.informativeText = "Headless Data-driven Native macOS Client for X.\nBuilt with pure SwiftUI, high performance GraphQL synchronization, and 120Hz micro-animations."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
