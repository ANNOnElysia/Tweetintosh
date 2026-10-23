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
    
    func toggleSidebar() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                self.sidebarExpanded.toggle()
            }
        }
    }
    
    // Shortcut HUD state (triggered by holding Option or Command)
    @Published var showShortcutHUD: Bool = false
    private var modHoldTimer: Timer?
    private var isModifierDown: Bool = false
    
    private var eventMonitor: Any?
    
    private init() {
        setupKeyboardMonitoring()
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        modHoldTimer?.invalidate()
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
    
    // MARK: - Global Shortcut & Option/Command Long-Press Engine
    private func setupKeyboardMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self = self else { return event }
            
            // Only handle if main window is active and lightbox is not presented
            guard !LightboxManager.shared.isPresented else {
                self.hideHUD()
                return event
            }
            
            // 1. Detect Option or Command key hold / release for Cheat Sheet HUD
            if event.type == .flagsChanged {
                let isModPressed = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command)
                
                if isModPressed && !self.isModifierDown {
                    self.isModifierDown = true
                    self.modHoldTimer?.invalidate()
                    // Schedule HUD appearance if held for > 0.70s
                    self.modHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.70, repeats: false) { [weak self] _ in
                        guard let self = self, self.isModifierDown else { return }
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                self.showShortcutHUD = true
                            }
                        }
                    }
                } else if !isModPressed && self.isModifierDown {
                    self.isModifierDown = false
                    self.hideHUD()
                }
                return event
            }
            
            // 2. Handle KeyDown events with Option (or Command fallback)
            if event.type == .keyDown {
                let hasOption = event.modifierFlags.contains(.option)
                let hasCmd = event.modifierFlags.contains(.command)
                let hasCtrl = event.modifierFlags.contains(.control)
                let keyCode = event.keyCode
                
                // If Esc key is pressed
                if keyCode == 53 {
                    if self.isSearchActive {
                        self.toggleSearch()
                        return nil
                    }
                    if self.showShortcutHUD {
                        self.hideHUD()
                        return nil
                    }
                }
                
                // Option + 1, 2, 3 / S / Left & Right Arrow (excluding Cmd+Ctrl combos)
                if hasOption || (hasCmd && !hasCtrl) {
                    switch keyCode {
                    case 18: // Key 1 -> Home
                        self.hideHUD()
                        self.selectTab(.home)
                        return nil
                        
                    case 19: // Key 2 -> Notifications
                        self.hideHUD()
                        self.selectTab(.notifications)
                        return nil
                        
                    case 20: // Key 3 -> Messages
                        self.hideHUD()
                        self.selectTab(.messages)
                        return nil
                        
                    case 1:  // S -> Search
                        self.hideHUD()
                        self.toggleSearch()
                        return nil
                        
                    case 123: // Left Arrow -> Slide to previous tab
                        self.hideHUD()
                        self.prevTab()
                        return nil
                        
                    case 124: // Right Arrow -> Slide to next tab
                        self.hideHUD()
                        self.nextTab()
                        return nil
                        
                    default:
                        break
                    }
                }
            }
            
            return event
        }
    }
    
    private func hideHUD() {
        modHoldTimer?.invalidate()
        modHoldTimer = nil
        if showShortcutHUD {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    self.showShortcutHUD = false
                }
            }
        }
    }
}
