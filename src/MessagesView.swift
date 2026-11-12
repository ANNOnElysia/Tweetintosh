//
//  MessagesView.swift
//  Tweetintosh
//
//  iMessage-inspired native Direct Messages (DMs) split view conforming strictly to Apple HIG.
//  Left pane: Filter dropdown, Edit/Pin mode, capsule search, X Chat 4-digit passcode banner & list.
//  Right pane: Contact header with Force Click Peek and click-to-profile, chat bubble stream, and action input dock.
//

import SwiftUI
import AppKit

private final class DMHoverState: ObservableObject {
    @Published var isHovered: Bool = false
}

struct MessagesView: View {
    var onOpenSettings: () -> Void
    var onLoginRequest: () -> Void
    
    @StateObject private var vm = DMViewModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    private let nav = NavigationManager.shared
    
    var body: some View {
        ZStack {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    if !nav.isContactListFolded {
                        // Left Column: Conversation Sidebar. It gives up width before the chat does, which matters
                        // when the app's sidebar is open in a half-screen window.
                        DMConversationListView()
                            .frame(width: min(max(proxy.size.width * 0.36, 230), 340))
                            .modifier(DMContactPanel())
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        
                        // Hairline Divider: a floating glass panel needs nothing to separate it
                        if !theme.usesGlassMessages {
                            Rectangle()
                                .fill(ThemeManager.divider)
                                .frame(width: 0.5)
                                .ignoresSafeArea()
                        }
                    }
                    
                    // Right Column: Chat Stream & Message Detail
                    DMChatDetailView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // Strict adherence to user's Tone (Minimalism = Pitch Black #000000 in dark mode)
            .background(ThemeManager.background.ignoresSafeArea())
            
            // The folded contact list, slid over the chat without resizing it. Picking a contact or clicking away closes it.
            if nav.isContactListFolded && nav.isContactListPeeking {
                Color.black.opacity(theme.isLight ? 0.12 : 0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeContactList() }
                    .transition(.opacity)
                    .zIndex(10)
                
                HStack(spacing: 0) {
                    Group {
                        if theme.usesGlassMessages {
                            DMConversationListView()
                                .frame(width: 290)
                                .modifier(DMContactPanel())
                        } else {
                            DMConversationListView()
                                .frame(width: 290)
                                .background(ThemeManager.background.ignoresSafeArea())
                                .shadow(color: Color.black.opacity(theme.isLight ? 0.18 : 0.5), radius: 16, x: 4)
                        }
                    }
                    .environment(\.peekScope, .contactListOverlay)
                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .leading))
                .zIndex(11)
            }
            
            // X Chat 4-Digit Passcode Modal Overlay
            if vm.showPasscodeSheet {
                DMPasscodeModalOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(999)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: vm.showPasscodeSheet)
        .onAppear {
            vm.loadInbox()
        }
        .environment(\.peekScope, .messages)
        .onChange(of: vm.selectedConversationId) { closeContactList() }
        .onDisappear { nav.isContactListPeeking = false }
    }
    
    private func closeContactList() {
        guard nav.isContactListPeeking else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            nav.isContactListPeeking = false
        }
    }
}

// MARK: - Liquid Glass

// With Liquid Glass on, the page follows the HIG's layering: messages and contacts are the content, and the controls float
// over them on glass, which content scrolls beneath. Off, it is the flat iMessage-style layout with dividers. Bubbles
// stay solid in both, because glass is for the controls layer and not for content itself.
extension ThemeManager {
    var usesGlassMessages: Bool {
        if #available(macOS 26.0, *) { return useLiquidGlass }
        return false
    }
}

// The contact list as a floating pane, lined up with the app's sidebar
private struct DMContactPanel: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared
    private let nav = NavigationManager.shared
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    func body(content: Content) -> some View {
        if theme.usesGlassMessages {
            content
                .clipShape(shape)
                .modifier(AdaptiveGlassModifier(isLiquid: true, shape: shape))
                .padding(.leading, nav.sidebarExpanded ? 6 : 12)
                .padding(.trailing, 4)
                .padding(.top, nav.sidebarExpanded ? 42 : 64)
                .padding(.bottom, 12)
        } else {
            content
        }
    }
}

// A control on glass in the Liquid Glass layout; the flat layout draws its own background, so this leaves it alone
private struct DMGlassControl<S: Shape>: ViewModifier {
    let shape: S
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        if theme.usesGlassMessages {
            content.modifier(AdaptiveGlassModifier(isLiquid: true, shape: shape))
        } else {
            content
        }
    }
}

// Glass can't sample other glass, so neighbouring pieces share a container to read as one material
private struct DMGlassGroup: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

// Shown where the contact list would be when the window is too narrow for it
private struct DMShowContactListButton: View {
    private let nav = NavigationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        if nav.isContactListFolded {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    nav.isContactListPeeking = true
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(ThemeManager.primaryText)
                    .frame(width: 32, height: 32)
                    .modifier(AdaptiveGlassModifier(isLiquid: theme.useLiquidGlass, shape: Circle()))
            }
            .buttonStyle(.target)
            .help(loc.t("messages_show_contacts"))
            .accessibilityLabel(loc.t("messages_show_contacts"))
        }
    }
}

// MARK: - Left Pane: Conversation List

private struct DMConversationListView: View {
    @ObservedObject private var vm = DMViewModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    private let nav = NavigationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar: Filter Dropdown + Edit Mode Pill
            // Safe clearance below window traffic lights and top floating capsule!
            HStack(alignment: .center, spacing: 10) {
                // 1. Filter Menu
                Menu {
                    ForEach(DMFilter.allCases) { f in
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                vm.filter = f
                            }
                        }) {
                            HStack {
                                Text(loc.t(f.locKey))
                                if vm.filter == f {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: vm.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(vm.filter == .all ? (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.70)) : ThemeManager.accent)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Spacer()
                
                // 2. Edit Button
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        vm.isEditMode.toggle()
                        if !vm.isEditMode {
                            vm.selectedConversationIds.removeAll()
                        }
                    }
                }) {
                    Text(loc.t(vm.isEditMode ? "messages_done" : "messages_edit"))
                        .font(theme.appFont(size: 12.5, weight: .medium))
                        .foregroundColor(ThemeManager.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.target)
            }
            .padding(.horizontal, 16)
            // Safe distance: accounts for macOS traffic lights & top floating droplet capsule
            .padding(.top, theme.usesGlassMessages ? 12 : (nav.sidebarExpanded ? 36 : 64))
            .padding(.bottom, 8)
            
            // Search Capsule Bar (iMessage style, clean and without microphone)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.isLight ? ThemeManager.secondaryText.opacity(0.70) : Color.white.opacity(0.40))
                
                TextField(loc.t("messages_search"), text: $vm.searchQuery)
                    .textFieldStyle(.plain)
                    .font(theme.appFont(size: 13, weight: .regular))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                
                if !vm.searchQuery.isEmpty {
                    Button(action: { vm.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(theme.isLight ? Color.black.opacity(0.35) : Color.white.opacity(0.40))
                    }
                    .buttonStyle(.target)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                // Already on the panel's glass, where more glass wouldn't show: a light fill marks the field
                if theme.usesGlassMessages {
                    Capsule().fill(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.10))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.isLight ? Color(hex: "#EAEAEB") : Color(hex: "#1C1C1E"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            
            // X Chat Passcode Unlock Banner (when not yet unlocked)
            if !vm.isPasscodeUnlocked {
                Button(action: { vm.promptPasscode() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 13))
                            .foregroundColor(ThemeManager.accent)
                        
                        Text(loc.t("messages_passcode_banner"))
                            .font(theme.appFont(size: 11.5, weight: .medium))
                            .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.90))
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                        
                        Text(loc.t("messages_passcode_unlock"))
                            .font(theme.appFont(size: 11.5, weight: .semibold))
                            .foregroundColor(ThemeManager.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.20))
                            )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(ThemeManager.accent.opacity(theme.isLight ? 0.08 : 0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(ThemeManager.accent.opacity(0.30), lineWidth: 0.75)
                            )
                    )
                }
                .buttonStyle(.target)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            
            // Batch Actions Bar (when Edit Mode is active)
            if vm.isEditMode {
                HStack(spacing: 8) {
                    Button(action: { vm.batchTogglePinSelected() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pin")
                            Text(loc.t("messages_pin"))
                        }
                        .font(theme.appFont(size: 11.5, weight: .medium))
                        .foregroundColor(ThemeManager.accent)
                    }
                    .buttonStyle(.target)
                    .disabled(vm.selectedConversationIds.isEmpty)
                    
                    Spacer()
                    
                    Button(action: { vm.batchMarkAsReadSelected() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.open")
                            Text(loc.t("messages_mark_read"))
                        }
                        .font(theme.appFont(size: 11.5, weight: .medium))
                        .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.80))
                    }
                    .buttonStyle(.target)
                    .disabled(vm.selectedConversationIds.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(ThemeManager.accent.opacity(theme.isLight ? 0.08 : 0.15))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Pinned Contacts Tray (iMessage circular avatar row)
            if !vm.pinnedConversations.isEmpty && vm.searchQuery.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.pinnedConversations) { conv in
                            Button(action: { vm.selectConversation(conv) }) {
                                VStack(spacing: 4) {
                                    ZStack {
                                        DMAvatarView(url: conv.avatarUrl, size: 50)
                                        if conv.id == vm.selectedConversationId {
                                            Circle()
                                                .stroke(ThemeManager.accent, lineWidth: 2)
                                                .frame(width: 54, height: 54)
                                        }
                                    }
                                    Text(conv.displayName)
                                        .font(theme.appFont(size: 11, weight: .medium))
                                        .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                                        .lineLimit(1)
                                        .frame(width: 56)
                                }
                            }
                            .buttonStyle(.target)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                
                if !theme.usesGlassMessages {
                    Rectangle()
                        .fill(ThemeManager.divider)
                        .frame(height: 0.5)
                }
            }
            
            // Conversation Scroll List
            ScrollView {
                LazyVStack(spacing: 2) {
                    if vm.isLoadingInbox && vm.conversations.isEmpty {
                        VStack(spacing: 10) {
                            LoadingIndicator()
                                .padding(.top, 40)
                        }
                    } else if vm.filteredConversations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(theme.isLight ? Color.black.opacity(0.20) : Color.white.opacity(0.20))
                                .padding(.top, 40)
                            Text(loc.t("messages_empty"))
                                .font(theme.appFont(size: 13, weight: .medium))
                                .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.50))
                        }
                    } else {
                        ForEach(vm.filteredConversations) { conv in
                            DMConversationRow(
                                conversation: conv,
                                isSelected: conv.id == vm.selectedConversationId,
                                isEditMode: vm.isEditMode,
                                isChecked: vm.selectedConversationIds.contains(conv.id),
                                onSelect: {
                                    // The release that ends a deep press on the avatar still arrives as a click
                                    guard !PeekCoordinator.shared.suppressesActivation else { return }
                                    if vm.isEditMode {
                                        if vm.selectedConversationIds.contains(conv.id) {
                                            vm.selectedConversationIds.remove(conv.id)
                                        } else {
                                            vm.selectedConversationIds.insert(conv.id)
                                        }
                                    } else {
                                        vm.selectConversation(conv)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Conversation Row

private struct DMConversationRow: View {
    let conversation: DMConversation
    let isSelected: Bool
    let isEditMode: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var vm = DMViewModel.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @StateObject private var hover = DMHoverState()
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Checkbox for Edit Mode
                if isEditMode {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isChecked ? ThemeManager.accent : (theme.isLight ? Color.black.opacity(0.25) : Color.white.opacity(0.30)))
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let other = conversation.otherParticipant {
                            DMAvatarView(url: conversation.avatarUrl, size: 44)
                                .peekable(.profile(other.asTweetUser))
                        } else {
                            DMAvatarView(url: conversation.avatarUrl, size: 44)
                        }
                    }
                    
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                            .padding(2.5)
                            .background(Circle().fill(ThemeManager.accent))
                            .offset(x: 2, y: 2)
                    }
                }
                
                // Text Block (iMessage style hierarchy)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(conversation.displayName)
                            .font(theme.appFont(size: 13.5, weight: .semibold))
                            .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                            .lineLimit(1)
                        
                        if conversation.otherParticipant?.isBlueVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#1D9BF0"))
                        }
                        
                        Spacer(minLength: 4)
                        
                        // Timestamp
                        Text(formatTimestamp(conversation.sortTimestamp))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(theme.isLight ? ThemeManager.secondaryText.opacity(0.80) : Color.white.opacity(0.45))
                    }
                    
                    HStack(alignment: .top, spacing: 4) {
                        if conversation.hasEncryptedMessages && !vm.isPasscodeUnlocked {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(ThemeManager.accent)
                                Text(loc.t("messages_locked_sidebar_hint"))
                                    .font(theme.appFont(size: 12, weight: .medium))
                                    .foregroundColor(ThemeManager.accent.opacity(theme.isLight ? 0.90 : 0.85))
                            }
                            .lineLimit(1)
                        } else {
                            Text(conversation.snippetText)
                                .font(theme.appFont(size: 12.5, weight: .regular))
                                .foregroundColor(
                                    isSelected
                                        ? (theme.isLight ? ThemeManager.primaryText.opacity(0.90) : Color.white.opacity(0.85))
                                        : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
                                )
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        
                        Spacer(minLength: 0)
                        
                        if conversation.unreadCount > 0 {
                            Circle()
                                .fill(ThemeManager.accent)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.target)
        .onHover { hover.isHovered = $0 }
        .contextMenu {
            Button(action: { vm.togglePin(for: conversation.id) }) {
                Label(loc.t(conversation.isPinned ? "messages_unpin" : "messages_pin"), systemImage: "pin")
            }
            if let other = conversation.otherParticipant {
                Button(action: { NavigationManager.shared.openProfile(other.asTweetUser) }) {
                    Label(other.formattedHandle, systemImage: "person.circle")
                }
            }
        }
    }
    
    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: theme.usesGlassMessages ? 14 : 10, style: .continuous)
        if isSelected {
            if theme.useLiquidGlass {
                shape
                    .fill(ThemeManager.accent.opacity(theme.isLight ? 0.16 : 0.22))
                    .overlay(shape.stroke(ThemeManager.accent.opacity(theme.usesGlassMessages ? 0 : 0.35), lineWidth: 0.75))
            } else {
                shape
                    .fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
            }
        } else if hover.isHovered {
            shape
                .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
        } else {
            Color.clear
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "MM/dd"
            return fmt.string(from: date)
        }
    }
}

// MARK: - Right Pane: Chat Detail & Input Dock

private struct DMChatDetailView: View {
    @ObservedObject private var vm = DMViewModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    private let nav = NavigationManager.shared
    
    @ViewBuilder private func glassChat(_ conv: DMConversation) -> some View {
        if #available(macOS 26.0, *) {
            Group {
                if conv.hasEncryptedMessages && !vm.isPasscodeUnlocked {
                    DMEncryptedGuidanceCard()
                } else {
                    DMBubbleScrollView(messages: vm.activeMessages)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(DMGlassChatBars(conversation: conv))
            .background(ThemeManager.background)
        }
    }
    
    var body: some View {
        if let conv = vm.selectedConversation, theme.usesGlassMessages {
            glassChat(conv)
        } else if let conv = vm.selectedConversation {
            VStack(spacing: 0) {
                // 1. Contact Top Header (with safe clearance below top floating capsule)
                DMContactHeader(conversation: conv)
                
                Rectangle()
                    .fill(ThemeManager.divider)
                    .frame(height: 0.5)
                
                // 2. Chat Bubble Stream or Encrypted Guidance
                if conv.hasEncryptedMessages && !vm.isPasscodeUnlocked {
                    DMEncryptedGuidanceCard()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DMBubbleScrollView(messages: vm.activeMessages)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Rectangle()
                    .fill(ThemeManager.divider)
                    .frame(height: 0.5)
                
                // 3. Bottom Input Dock
                DMInputDock()
            }
            .background(ThemeManager.background)
        } else {
            // Empty State
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(theme.isLight ? Color.black.opacity(0.18) : Color.white.opacity(0.18))
                Text(loc.t("messages_select_prompt"))
                    .font(theme.appFont(size: 14, weight: .medium))
                    .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.50))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, nav.sidebarExpanded ? 14 : 64)
            .background(ThemeManager.background)
            .overlay(alignment: .topLeading) {
                DMShowContactListButton()
                    .padding(.leading, 16)
                    .padding(.top, nav.sidebarExpanded ? 14 : 64)
            }
        }
    }
}

// MARK: - End-to-End Encrypted Guidance Card

@available(macOS 26.0, *)
private struct DMGlassChatBars: ViewModifier {
    let conversation: DMConversation

    func body(content: Content) -> some View {
        // Bars rather than a stack, so messages scroll beneath the glass under the system's scroll edge effect
        content
            .safeAreaBar(edge: .top) { DMContactHeader(conversation: conversation) }
            .safeAreaBar(edge: .bottom) { DMInputDock() }
    }
}

private struct DMEncryptedGuidanceCard: View {
    @ObservedObject private var vm = DMViewModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.20))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(ThemeManager.accent)
            }
            .padding(.bottom, 4)
            
            VStack(spacing: 6) {
                Text(loc.t("messages_locked_card_title"))
                    .font(theme.appFont(size: 17, weight: .bold))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                
                Text(loc.t("messages_locked_card_desc"))
                    .font(theme.appFont(size: 13, weight: .regular))
                    .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }
            
            Button(action: {
                vm.promptPasscode()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(loc.t("messages_locked_card_action"))
                        .font(theme.appFont(size: 13.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(ThemeManager.accent)
                .clipShape(Capsule())
                .shadow(color: ThemeManager.accent.opacity(theme.isLight ? 0.25 : 0.40), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.target)
            .padding(.top, 8)
        }
        .frame(maxWidth: 380)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .background(guidanceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(24)
    }
    
    @ViewBuilder
    private var guidanceBackground: some View {
        if theme.useLiquidGlass {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.isLight ? Color.white.opacity(0.60) : Color.white.opacity(0.12), lineWidth: 0.75)
                )
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.isLight ? Color(hex: "#F4F4F6") : Color(hex: "#18181A"))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.10), lineWidth: 0.75)
                )
        }
    }
}

// MARK: - Contact Top Header (with Click to Profile, Force Click Peek & Lock Indicator)

private struct DMContactHeader: View {
    let conversation: DMConversation
    @ObservedObject private var vm = DMViewModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    private let nav = NavigationManager.shared
    @StateObject private var hover = DMHoverState()
    
    var body: some View {
        HStack(spacing: 10) {
            DMShowContactListButton()
            
            if let other = conversation.otherParticipant {
                Button(action: {
                    NavigationManager.shared.openProfile(other.asTweetUser)
                }) {
                    HStack(spacing: 10) {
                        DMAvatarView(url: conversation.avatarUrl, size: 36)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(conversation.displayName)
                                    .font(theme.appFont(size: 13.5, weight: .semibold))
                                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                                    .lineLimit(1)
                                
                                if other.isBlueVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(Color(hex: "#1D9BF0"))
                                }
                            }
                            
                            Text(other.formattedHandle)
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.50))
                        }
                    }
                    .padding(.leading, theme.usesGlassMessages ? 5 : 8)
                    .padding(.trailing, theme.usesGlassMessages ? 14 : 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hover.isHovered && !theme.usesGlassMessages ? (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08)) : Color.clear)
                    )
                }
                .buttonStyle(.target)
                .modifier(DMGlassControl(shape: Capsule()))
                .onHover { hover.isHovered = $0 }
                .peekable(.profile(other.asTweetUser)) // Deep-press / Force Click Peek card!
            } else {
                Text(conversation.displayName)
                    .font(theme.appFont(size: 14, weight: .semibold))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
            }
            
            Spacer()
            
            // X Chat Passcode Lock Status Button / Indicator
            if !vm.isPasscodeUnlocked {
                Button(action: {
                    vm.promptPasscode()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(loc.t("messages_locked_header_btn"))
                            .font(theme.appFont(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(ThemeManager.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if !theme.usesGlassMessages {
                            Capsule()
                                .fill(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.20))
                                .overlay(
                                    Capsule()
                                        .stroke(ThemeManager.accent.opacity(0.35), lineWidth: 0.75)
                                )
                        }
                    }
                    .modifier(DMGlassControl(shape: Capsule()))
                }
                .buttonStyle(.target)
            }
        }
        .padding(.horizontal, 16)
        // Generous safe distance: fully clears the top floating capsule!
        .padding(.top, theme.usesGlassMessages ? (nav.sidebarExpanded ? 42 : 64) : (nav.sidebarExpanded ? 14 : 64))
        .padding(.bottom, 10)
    }
}

// MARK: - Bubble Stream

private struct DMBubbleScrollView: View {
    let messages: [DMMessage]
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    /// Only messages are drawn as bubbles. Reactions, edits and read marks arrive as entries of their own and are
    /// applied to the message they name; a message shows its author's latest edit.
    private var bubbles: [DMMessage] {
        var latestEdit: [String: DMMessage] = [:]
        var deleted = Set<String>()
        for entry in messages {
            if entry.entryKind == .edit, let target = entry.targetSequenceId { latestEdit[target] = entry }
            if entry.entryKind == .delete { deleted.formUnion(entry.deletedSequenceIds ?? []) }
        }
        return messages.compactMap { msg in
            guard msg.entryKind == .message else { return nil }
            if let seq = msg.sequenceId, deleted.contains(seq) { return nil }
            if let seq = msg.sequenceId, let edit = latestEdit[seq], edit.senderId == msg.senderId {
                return msg.edited(to: edit.text, at: edit.createdAt)
            }
            return msg
        }
    }
    
    /// Each message's reactions, keyed by message id, replayed in order: a person holds one reaction per message,
    /// so a later one replaces the earlier, and a removal takes theirs away.
    private var reactionsByMessage: [String: [DMMessage]] {
        var result: [String: [DMMessage]] = [:]
        for entry in messages where entry.entryKind == .reaction || entry.entryKind == .reactionRemove {
            guard let targetId = entry.targetSequenceId,
                  let target = messages.last(where: { $0.entryKind == .message && $0.isTarget(of: targetId) }) else {
                // The target is older than what is loaded; there is nothing on screen to attach it to.
                continue
            }
            var list = result[target.id] ?? []
            if entry.entryKind == .reaction {
                list.removeAll { $0.senderId == entry.senderId }
                list.append(entry)
            } else {
                list.removeAll { $0.senderId == entry.senderId && $0.emoji == entry.emoji }
            }
            result[target.id] = list
        }
        return result
    }
    
    /// "Seen" only once a read receipt covers the last message, "Sent" until then.
    private func status(for msg: DMMessage) -> String? {
        guard msg.isOutgoing, !msg.isEncrypted else { return nil }
        let seen = !DMSeen.seenTimes(for: msg, among: messages, receipts: vm.session.receipts).isEmpty
        return loc.t(seen ? "messages_seen" : "messages_sent_status")
    }
    
    var body: some View {
        let bubbles = bubbles
        let reactions = reactionsByMessage
        let lastStatus = bubbles.last.flatMap { status(for: $0) }
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(bubbles) { msg in
                        DMBubbleRow(message: msg, status: msg.id == bubbles.last?.id ? lastStatus : nil, reactions: reactions[msg.id] ?? [])
                            .modifier(DMMessageMenuDimming(messageId: msg.id))
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("AppWindow"))
            } action: { frame in
                DMMessageMenuManager.shared.viewport = frame
            }
            .onAppear {
                if let last = bubbles.last {
                    scrollProxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: messages.count) {
                if let last = bubbles.last {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        scrollProxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Message Bubble Row (iMessage Speech Bubble Shape & Colors)

private struct DMBubbleRow: View {
    let message: DMMessage
    /// "Sent" or "Seen" under the last message, when it is one's own.
    let status: String?
    let reactions: [DMMessage]
    
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 6) {
                if message.isEncrypted {
                    if message.isOutgoing {
                        Spacer(minLength: 48)
                        encryptedBubble
                            .modifier(DMMessageMenuAnchor(message: message, reactions: reactions))
                    } else {
                        encryptedBubble
                            .modifier(DMMessageMenuAnchor(message: message, reactions: reactions))
                        Spacer(minLength: 48)
                    }
                } else if message.isOutgoing {
                    Spacer(minLength: 48)
                    outgoingBubble
                        .modifier(DMReactionAttachment(message: message, reactions: reactions, isOutgoing: true))
                        .modifier(DMMessageMenuAnchor(message: message, reactions: reactions))
                } else {
                    incomingBubble
                        .modifier(DMReactionAttachment(message: message, reactions: reactions, isOutgoing: false))
                        .modifier(DMMessageMenuAnchor(message: message, reactions: reactions))
                    Spacer(minLength: 48)
                }
            }
            
            if let status {
                Text(status)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(theme.isLight ? ThemeManager.secondaryText.opacity(0.80) : Color.white.opacity(0.40))
                    .padding(.trailing, 6)
            }
        }
    }
    
    // Encrypted placeholder bubble with interactive tap-to-unlock guidance
    private var encryptedBubble: some View {
        Button(action: {
            if DMViewModel.shared.isPasscodeUnlocked {
                DMViewModel.shared.decryptAllLoadedMessages()
            } else {
                DMViewModel.shared.promptPasscode()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeManager.accent)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("messages_encrypted_notice"))
                        .font(theme.appFont(size: 13, weight: .semibold))
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                    Text(loc.t("messages_locked_bubble_hint"))
                        .font(theme.appFont(size: 11, weight: .regular))
                        .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.60))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ThemeManager.accent.opacity(theme.isLight ? 0.08 : 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ThemeManager.accent.opacity(0.28), lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.target)
    }
    
    // Outgoing bubble (follower of user's chosen Theme Accent Color, iMessage corner contour)
    private var outgoingBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            DMBubbleAttribution(message: message, onAccent: true)
            if let media = message.mediaUrl, !media.isEmpty {
                CachedAsyncImage(
                    urlString: media,
                    placeholderColor: Color.gray.opacity(0.2),
                    contentMode: .fill,
                    targetSize: CGSize(width: 240, height: 180)
                )
                .frame(maxWidth: 240, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !message.text.isEmpty {
                Text(message.formattedText)
                    .font(theme.appFont(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8.5)
            }
        }
        .background(
            ThemeManager.accent
        )
        .clipShape(RoundedCorner(tl: 18, tr: 18, bl: 18, br: 4))
        .shadow(color: ThemeManager.accent.opacity(theme.isLight ? 0.15 : 0.30), radius: 5, x: 0, y: 2)
    }
    
    // Incoming bubble (authentic Apple iMessage bubble: #262628 in dark mode)
    private var incomingBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            DMBubbleAttribution(message: message, onAccent: false)
            if let media = message.mediaUrl, !media.isEmpty {
                CachedAsyncImage(
                    urlString: media,
                    placeholderColor: Color.gray.opacity(0.2),
                    contentMode: .fill,
                    targetSize: CGSize(width: 240, height: 180)
                )
                .frame(maxWidth: 240, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !message.text.isEmpty {
                Text(message.formattedText)
                    .font(theme.appFont(size: 14, weight: .regular))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.96))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8.5)
            }
        }
        .background(incomingBackground)
        .clipShape(RoundedCorner(tl: 18, tr: 18, bl: 4, br: 18))
    }
    
    @ViewBuilder
    private var incomingBackground: some View {
        if theme.useLiquidGlass {
            RoundedCorner(tl: 18, tr: 18, bl: 4, br: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedCorner(tl: 18, tr: 18, bl: 4, br: 18)
                        .stroke(
                            theme.isLight ? Color.white.opacity(0.70) : Color.white.opacity(0.14),
                            lineWidth: 0.75
                        )
                )
        } else {
            // Mode B: Non-Liquid Glass HIG neutral bubble (#262628 for dark, #E5E5EA for light)
            RoundedCorner(tl: 18, tr: 18, bl: 4, br: 18)
                .fill(theme.isLight ? Color(hex: "#E5E5EA") : Color(hex: "#262628"))
        }
    }
}

// MARK: - Reply Quote & Forward Label

/// What sits above a bubble's text: "Forwarded" for a forward, and the quoted message for a reply.
private struct DMBubbleAttribution: View {
    let message: DMMessage
    let onAccent: Bool
    
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    private var secondary: Color {
        onAccent ? Color.white.opacity(0.78) : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
    }
    
    var body: some View {
        if message.isForwarded == true || message.replyPreview != nil {
            VStack(alignment: .leading, spacing: 5) {
                if message.isForwarded == true {
                    Label(loc.t("messages_forwarded_label"), systemImage: "arrowshape.turn.up.right")
                        .font(theme.appFont(size: 11, weight: .medium))
                        .foregroundColor(secondary)
                }
                if let reply = message.replyPreview {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(onAccent ? Color.white.opacity(0.7) : ThemeManager.accent)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reply.senderName)
                                .font(theme.appFont(size: 11.5, weight: .semibold))
                                .foregroundColor(onAccent ? .white : (theme.isLight ? ThemeManager.primaryText : .white))
                                .lineLimit(1)
                            Text(reply.text)
                                .font(theme.appFont(size: 12, weight: .regular))
                                .foregroundColor(secondary)
                                .lineLimit(2)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(onAccent ? Color.white.opacity(0.16) : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08)))
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, -2)
        }
    }
}

// MARK: - Reaction Badge

/// Hangs a message's reactions off the bottom edge of its bubble, on the side the bubble's tail points to, the way
/// X's own chat does. The row grows by the overhang so the badge never sits on top of the next message.
private struct DMReactionAttachment: ViewModifier {
    let message: DMMessage
    let reactions: [DMMessage]
    let isOutgoing: Bool
    
    @ObservedObject private var theme = ThemeManager.shared
    
    private static let overhang: CGFloat = 12
    
    /// Distinct emoji in the order they were first used, each with how many people chose it.
    private var groups: [(emoji: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for r in reactions {
            guard let e = r.emoji else { continue }
            if counts[e] == nil { order.append(e) }
            counts[e, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }
    
    private var myEmoji: String? {
        reactions.first { $0.isOutgoing }?.emoji
    }
    
    func body(content: Content) -> some View {
        if reactions.isEmpty {
            content
        } else {
            content
                .padding(.bottom, Self.overhang)
                .overlay(alignment: isOutgoing ? .bottomTrailing : .bottomLeading) {
                    badge
                        .padding(isOutgoing ? .trailing : .leading, 10)
                }
        }
    }
    
    private var badge: some View {
        HStack(spacing: 3) {
            ForEach(groups, id: \.emoji) { group in
                let label = HStack(spacing: 1) {
                    Text(group.emoji)
                        .font(.system(size: 12))
                    if group.count > 1 {
                        Text("\(group.count)")
                            .font(theme.appFont(size: 10, weight: .semibold))
                            .foregroundColor(ThemeManager.secondaryText)
                    }
                }
                // Clicking your own reaction takes it back
                if group.emoji == myEmoji {
                    Button {
                        DMViewModel.shared.toggleReaction(group.emoji, on: message, current: group.emoji)
                    } label: {
                        label.contentShape(Rectangle())
                    }
                    .buttonStyle(.target)
                } else {
                    label
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous)
                .fill(ThemeManager.background)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(ThemeManager.divider, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.30), radius: 2, x: 0, y: 1)
        .help(groups.map(\.emoji).joined(separator: " "))
    }
}

// MARK: - Input Dock (iMessage Capsule Style)

private struct DMInputDock: View {
    @ObservedObject private var vm = DMViewModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            if let reply = vm.replyingTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeManager.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(loc.format("messages_replying_to", ["name": vm.displayName(of: reply.senderId, in: reply.conversationId)]))
                            .font(theme.appFont(size: 11.5, weight: .semibold))
                            .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                        Text(reply.text)
                            .font(theme.appFont(size: 11.5, weight: .regular))
                            .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button(action: { vm.replyingTo = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(theme.isLight ? Color.black.opacity(0.30) : Color.white.opacity(0.35))
                    }
                    .buttonStyle(.target)
                    .keyboardShortcut(.cancelAction)
                    .help(loc.t("messages_cancel"))
                }
                .padding(.horizontal, theme.usesGlassMessages ? 14 : 18)
                .padding(.vertical, theme.usesGlassMessages ? 8 : 0)
                .modifier(DMGlassControl(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
                .padding(.horizontal, theme.usesGlassMessages ? 14 : 0)
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Pending media attachments preview
            if !vm.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.pendingAttachments.enumerated()), id: \.offset) { idx, url in
                            ZStack(alignment: .topTrailing) {
                                if let img = NSImage(contentsOf: url) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 52, height: 52)
                                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                }
                                
                                Button(action: { vm.removeAttachment(at: idx) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.70)))
                                }
                                .buttonStyle(.target)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
            }
            
            HStack(alignment: theme.usesGlassMessages ? .center : .bottom, spacing: 8) {
                // 1. Plus Action Button (directly opens Finder via NSOpenPanel, supports ⌥A)
                Button(action: {
                    MediaAttachments.pick(parent: NSApp.keyWindow) { urls in
                        vm.attachMedia(urls)
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.70))
                        .frame(width: theme.usesGlassMessages ? 36 : 30, height: theme.usesGlassMessages ? 36 : 30)
                        .background {
                            if !theme.usesGlassMessages {
                                Circle()
                                    .fill(theme.isLight ? Color.black.opacity(0.06) : Color(hex: "#262628"))
                            }
                        }
                        .modifier(DMGlassControl(shape: Circle()))
                }
                .buttonStyle(.target)
                .keyboardShortcut("a", modifiers: [.option])
                .help(loc.t("attach_media") + " (⌥A)")
                
                // 2. Message Input Capsule
                HStack(spacing: 6) {
                    TextField(loc.t("messages_input_placeholder"), text: $vm.inputText)
                        .textFieldStyle(.plain)
                        .font(theme.appFont(size: 13.5, weight: .regular))
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                        .focused($isInputFocused)
                        .onSubmit {
                            vm.sendMessage()
                        }
                        // Choosing Reply puts the cursor where the reply is typed.
                        .onChange(of: vm.replyingTo?.id) {
                            if vm.replyingTo != nil { isInputFocused = true }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, theme.usesGlassMessages ? 10 : 7)
                .background {
                    if !theme.usesGlassMessages {
                        Capsule()
                            .fill(theme.isLight ? Color(hex: "#E5E5EA") : Color(hex: "#1C1C1E"))
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isInputFocused
                                            ? ThemeManager.accent.opacity(0.60)
                                            : (theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12)),
                                        lineWidth: 0.75
                                    )
                            )
                    }
                }
                .modifier(DMGlassControl(shape: Capsule()))
                
                // 3. Send Up-Arrow Button (iMessage upward circle)
                let canSend = !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.pendingAttachments.isEmpty
                Button(action: {
                    vm.sendMessage()
                }) {
                    if theme.usesGlassMessages, #available(macOS 26.0, *) {
                        // The one prominent action, so the one tinted piece of glass
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(canSend ? ThemeManager.onAccent : (theme.isLight ? Color.black.opacity(0.25) : Color.white.opacity(0.30)))
                            .frame(width: 36, height: 36)
                            .tweetGlass(canSend ? .regular.tint(ThemeManager.accent).interactive() : .regular, in: Circle())
                            .animation(.spring(response: 0.20, dampingFraction: 0.75), value: canSend)
                    } else {
    Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(canSend ? ThemeManager.accent : (theme.isLight ? Color.black.opacity(0.15) : Color.white.opacity(0.20)))
                            .scaleEffect(canSend ? 1.05 : 1.0)
                            .animation(.spring(response: 0.20, dampingFraction: 0.75), value: canSend)
                    }
                }
                .buttonStyle(.target)
                .disabled(!canSend || vm.isSending)
            }
            .modifier(DMGlassGroup())
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - X Chat 4-Digit Passcode Modal Overlay

private final class PasscodeState: ObservableObject {
    @Published var code: String = ""
    var eventMonitor: Any? = nil
}

private struct DMPasscodeModalOverlay: View {
    @ObservedObject private var vm = DMViewModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @StateObject private var state = PasscodeState()
    
    var body: some View {
        ZStack {
            // Dark Backdrop Dismissal
            Color.black.opacity(0.60)
                .ignoresSafeArea()
                .onTapGesture {
                    if !vm.isVerifyingPasscode {
                        vm.showPasscodeSheet = false
                    }
                }
            
            // Passcode Card
            VStack(spacing: 20) {
                // Header Lock Icon
                ZStack {
                    Circle()
                        .fill(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.20))
                        .frame(width: 58, height: 58)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 26))
                        .foregroundColor(ThemeManager.accent)
                }
                .padding(.top, 4)
                
                // Titles
                VStack(spacing: 6) {
                    Text(loc.t("messages_passcode_title"))
                        .font(theme.appFont(size: 17, weight: .semibold))
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                    
                    Text(loc.t("messages_passcode_subtitle"))
                        .font(theme.appFont(size: 12.5, weight: .regular))
                        .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.60))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                
                // 4 PIN Dots or Verifying Spinner
                VStack(spacing: 8) {
                    if vm.isVerifyingPasscode {
                        // Wraps rather than being cut short: the card is narrow, and some languages need two lines
                        HStack(spacing: 8) {
                            LoadingIndicator(compactHeight: 16)
                            Text(loc.t("messages_verifying_passcode"))
                                .font(theme.appFont(size: 12.5, weight: .medium))
                                .foregroundColor(ThemeManager.accent)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 20)
                    } else {
                        HStack(spacing: 18) {
                            ForEach(0..<4, id: \.self) { index in
                                let isFilled = index < state.code.count
                                Circle()
                                    .fill(isFilled ? ThemeManager.accent : Color.clear)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                isFilled ? ThemeManager.accent : (theme.isLight ? Color.black.opacity(0.30) : Color.white.opacity(0.35)),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .scaleEffect(isFilled ? 1.15 : 1.0)
                                    .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isFilled)
                            }
                        }
                        .frame(height: 20)
                    }
                    
                    if let error = vm.passcodeErrorMessage {
                        Text(error)
                            .font(theme.appFont(size: 12, weight: .medium))
                            .foregroundColor(Color.red.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
                
                // Numeric Keypad
                VStack(spacing: 12) {
                    keypadRow(["1", "2", "3"])
                    keypadRow(["4", "5", "6"])
                    keypadRow(["7", "8", "9"])
                    
                    HStack(spacing: 16) {
                        // Cancel
                        Button(action: {
                            if !vm.isVerifyingPasscode {
                                vm.showPasscodeSheet = false
                            }
                        }) {
                            Text(loc.t("messages_passcode_cancel"))
                                .font(theme.appFont(size: 13, weight: .medium))
                                .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.70))
                                .frame(width: 58, height: 58)
                        }
                        .buttonStyle(.target)
                        .disabled(vm.isVerifyingPasscode)
                        
                        // 0
                        keypadButton("0")
                        
                        // Delete
                        Button(action: {
                            guard !vm.isVerifyingPasscode else { return }
                            if !state.code.isEmpty {
                                state.code.removeLast()
                                vm.passcodeErrorMessage = nil
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                        }) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                                .frame(width: 58, height: 58)
                                .background(
                                    Circle()
                                        .fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.target)
                        .disabled(vm.isVerifyingPasscode)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(width: 320)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.40), radius: 30, x: 0, y: 12)
        }
        .onAppear {
            state.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard vm.showPasscodeSheet else { return event }
                if event.keyCode == 53 { // Esc
                    if !vm.isVerifyingPasscode {
                        vm.showPasscodeSheet = false
                    }
                    return nil
                }
                if event.keyCode == 51 { // Backspace
                    if !vm.isVerifyingPasscode && !state.code.isEmpty {
                        state.code.removeLast()
                        vm.passcodeErrorMessage = nil
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    return nil
                }
                if let chars = event.characters, chars.count == 1, let char = chars.first, char.isNumber {
                    handleDigit(String(char))
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = state.eventMonitor {
                NSEvent.removeMonitor(monitor)
                state.eventMonitor = nil
            }
        }
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if theme.useLiquidGlass {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(theme.isLight ? Color.white.opacity(0.80) : Color.white.opacity(0.18), lineWidth: 0.75)
                )
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.isLight ? Color(hex: "#F8F8F6") : Color(hex: "#1A1A1D"))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.14), lineWidth: 0.75)
                )
        }
    }
    
    private func keypadRow(_ digits: [String]) -> some View {
        HStack(spacing: 16) {
            ForEach(digits, id: \.self) { digit in
                keypadButton(digit)
            }
        }
    }
    
    private func keypadButton(_ digit: String) -> some View {
        Button(action: {
            handleDigit(digit)
        }) {
            Text(digit)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.target)
        .disabled(vm.isVerifyingPasscode)
    }
    
    private func handleDigit(_ digit: String) {
        guard !vm.isVerifyingPasscode else { return }
        if vm.passcodeErrorMessage != nil {
            vm.passcodeErrorMessage = nil
            state.code.removeAll()
        }
        guard state.code.count < 4 else { return }
        state.code.append(digit)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        
        if state.code.count == 4 {
            let finalCode = state.code
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                vm.unlockWithPasscode(finalCode) { success in
                    if !success {
                        state.code.removeAll()
                    }
                }
            }
        }
    }
}

// MARK: - Reusable Avatar View

struct DMAvatarView: View {
    let url: String?
    let size: CGFloat
    
    var body: some View {
        CachedAsyncImage(
            urlString: url,
            placeholderColor: Color.gray.opacity(0.25),
            contentMode: .fill,
            targetSize: CGSize(width: size, height: size)
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
}
