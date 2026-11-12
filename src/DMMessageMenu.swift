//
//  DMMessageMenu.swift
//  Tweetintosh
//
//  The menu a chat message opens on a deep press (Force Click), or on a secondary click for trackpads and mice
//  without Force Touch, modelled on the X iOS app's message menu without Report and Ask Grok. While it is open the
//  pressed bubble lifts and the rest of the chat fades. Info turns the menu into a card with the sender, when the
//  message was sent and when it was seen.
//
//  Bubbles only record their frames here; one event monitor finds the bubble under the pointer, the same way
//  `PeekCoordinator` does for posts, so no AppKit view is added per row.
//

import SwiftUI
import AppKit

// MARK: - Manager

struct DMMessageMenuPayload: Equatable {
    let message: DMMessage
    let reactions: [DMMessage]
    let anchorRect: CGRect
}

/// What the card shows: the action list, or what one of the actions opened in its place.
enum DMMessageMenuMode {
    case actions, info, forward, delete

    var width: CGFloat {
        switch self {
        case .actions: return 236
        case .info: return 270
        case .forward: return 260
        case .delete: return 220
        }
    }
}

final class DMMessageMenuManager: ObservableObject {
    static let shared = DMMessageMenuManager()

    @Published private(set) var active: DMMessageMenuPayload?
    @Published var mode = DMMessageMenuMode.actions
    var cardFrame: CGRect = .zero
    // Measured, so the card can be placed above a bubble near the bottom without overlapping it
    @Published var cardSize = CGSize(width: 200, height: 80)

    private struct Anchor {
        var frame: CGRect
        var message: DMMessage
        var reactions: [DMMessage]
    }

    // Bubble frames in the "AppWindow" space, and the visible part of the chat. Rows a LazyVStack keeps alive just
    // outside the viewport sit under the header or input dock, so a hit must also fall inside the viewport.
    private var anchors: [String: Anchor] = [:]
    var viewport: CGRect = .zero

    private var monitor: Any?
    private var lastStage = 0

    private init() {}

    func register(_ message: DMMessage, reactions: [DMMessage], frame: CGRect) {
        anchors[message.id] = Anchor(frame: frame, message: message, reactions: reactions)
        startMonitoring()
    }

    func unregister(_ messageId: String) {
        anchors.removeValue(forKey: messageId)
    }

    func present(_ anchor: CGRect, message: DMMessage, reactions: [DMMessage]) {
        mode = .actions
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            active = DMMessageMenuPayload(message: message, reactions: reactions, anchorRect: anchor)
        }
    }

    func dismiss() {
        guard active != nil else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            active = nil
        }
    }

    // MARK: Events

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.pressure, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            // Not `self?.handle(event) ?? event`: that turns a swallowed event (nil) back into the event, so Esc
            // would still reach the window and beep.
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .pressure:
            let stage = event.stage
            if stage >= 2 && lastStage < 2 && active == nil, let hit = anchor(at: event) {
                present(hit.frame, message: hit.message, reactions: hit.reactions)
            }
            lastStage = stage
            return event

        case .rightMouseDown:
            if active != nil {
                if cardContains(event) { return event }
                dismiss()
            }
            if let hit = anchor(at: event) {
                present(hit.frame, message: hit.message, reactions: hit.reactions)
                return nil
            }
            return event

        case .leftMouseDown:
            lastStage = 0
            // A click outside closes the menu and goes no further, so it never also lands on what is underneath.
            if active != nil && !cardContains(event) {
                dismiss()
                return nil
            }
            return event

        case .scrollWheel:
            if active != nil && !cardContains(event) { dismiss() }
            return event

        case .keyDown:
            if active != nil && event.keyCode == 53 { // Esc
                dismiss()
                return nil
            }
            return event

        default:
            return event
        }
    }

    private func point(for event: NSEvent) -> CGPoint? {
        guard let window = event.window, window === NSApp.mainWindow,
              let origin = AppWindowOrigin.windowRect else { return nil }
        let p = event.locationInWindow
        return CGPoint(x: p.x - origin.minX, y: origin.maxY - p.y)
    }

    private func cardContains(_ event: NSEvent) -> Bool {
        guard let p = point(for: event) else { return false }
        return cardFrame.contains(p)
    }

    private func anchor(at event: NSEvent) -> Anchor? {
        let nav = NavigationManager.shared
        // Messages behind the slide-over contact list or a profile preview are out of reach: only what is in front answers
        guard nav.currentTab == .messages, !nav.hasOverlay, !nav.isShowingCompose,
              !nav.isContactListPeeking, PeekCoordinator.shared.target == nil,
              !DMViewModel.shared.showPasscodeSheet,
              event.window?.attachedSheet == nil,
              let p = point(for: event), viewport.contains(p) else { return nil }
        return anchors.values.first { $0.frame.contains(p) }
    }
}

// MARK: - Reactions

/// The emoji at the top of the menu: the ones used most recently, topped up with the reactions X has always offered.
enum DMRecentReactions {
    private static let defaultsKey = "Tweetintosh_RecentReactions"
    private static let defaults = ["😂", "😲", "😢", "❤️", "🔥", "👍", "👎"]
    private static let rowLength = 6

    private static var recent: [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    /// The row to show. A reaction already on the message always appears, so it can be seen and taken back.
    static func row(including chosen: String?) -> [String] {
        var row: [String] = []
        for emoji in recent + defaults where !row.contains(emoji) && row.count < rowLength {
            row.append(emoji)
        }
        if let chosen, !row.contains(chosen) {
            row[row.count - 1] = chosen
        }
        return row
    }

    static func record(_ emoji: String) {
        let updated = [emoji] + recent.filter { $0 != emoji }
        UserDefaults.standard.set(Array(updated.prefix(rowLength)), forKey: defaultsKey)
    }
}

/// Opens the system Emoji & Symbols panel for the menu. The panel types into whichever text view has focus, so an
/// invisible one holds the focus and passes on what arrives, keeping only emoji (the panel also offers symbols).
final class DMEmojiCatcher: ObservableObject {
    fileprivate weak var textView: DMEmojiCatcherTextView?

    func open(onPick: @escaping (String) -> Void) {
        guard let textView, let window = textView.window else { return }
        textView.onPick = onPick
        window.makeFirstResponder(textView)
        textView.inputContext?.activate()
        // The panel attaches to the active text input, which macOS connects a moment after the focus changes; asked
        // any sooner, it doesn't open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

fileprivate final class DMEmojiCatcherTextView: NSTextView {
    var onPick: ((String) -> Void)?

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let isEmoji = text.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
        guard isEmoji else { return }
        onPick?(text)
    }
}

private struct DMEmojiCatcherView: NSViewRepresentable {
    let catcher: DMEmojiCatcher

    func makeNSView(context: Context) -> NSView {
        // In a plain container so it stays tiny: at the right end of the row, which puts the panel under the arrow
        let container = NSView()
        let textView = DMEmojiCatcherTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 16))
        textView.drawsBackground = false
        textView.insertionPointColor = .clear
        textView.autoresizingMask = [.minXMargin]
        container.addSubview(textView)
        catcher.textView = textView
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        catcher.textView?.frame.origin.x = max(0, view.bounds.width - 16)
    }
}

// MARK: - Bubble Hooks

/// Records a bubble's frame for the menu, and lifts the bubble while its menu is open.
struct DMMessageMenuAnchor: ViewModifier {
    let message: DMMessage
    let reactions: [DMMessage]

    @ObservedObject private var menu = DMMessageMenuManager.shared

    func body(content: Content) -> some View {
        let isFocused = menu.active?.message.id == message.id
        content
            .scaleEffect(isFocused ? 1.04 : 1.0, anchor: message.isOutgoing ? .trailing : .leading)
            .shadow(color: Color.black.opacity(isFocused ? 0.18 : 0), radius: 12, x: 0, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isFocused)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("AppWindow"))
            } action: { frame in
                DMMessageMenuManager.shared.register(message, reactions: reactions, frame: frame)
            }
            .onDisappear {
                DMMessageMenuManager.shared.unregister(message.id)
            }
    }
}

/// Fades every message but the one whose menu is open, the macOS counterpart of iOS blurring the chat behind it.
struct DMMessageMenuDimming: ViewModifier {
    let messageId: String

    @ObservedObject private var menu = DMMessageMenuManager.shared

    func body(content: Content) -> some View {
        let dimmed = menu.active != nil && menu.active?.message.id != messageId
        content
            .opacity(dimmed ? 0.3 : 1.0)
            .animation(.easeOut(duration: 0.18), value: dimmed)
    }
}

// MARK: - Overlay (rendered in AppRootView)

struct DMMessageMenuOverlay: View {
    @ObservedObject private var manager = DMMessageMenuManager.shared

    var body: some View {
        GeometryReader { geo in
            if let payload = manager.active {
                card(payload, container: geo.size)
            }
        }
        .allowsHitTesting(manager.active != nil)
    }

    @ViewBuilder
    private func card(_ payload: DMMessageMenuPayload, container: CGSize) -> some View {
        let width = manager.mode.width
        let height = manager.cardSize.height
        let anchor = payload.anchorRect
        let gap: CGFloat = 8

        // Line the card up with the bubble's own side, below it when it fits, otherwise above, otherwise as low as
        // the window allows (a bubble taller than the window leaves no room either side).
        let x = min(max(payload.message.isOutgoing ? anchor.maxX - width : anchor.minX, 12), container.width - width - 12)
        let fitsBelow = anchor.maxY + gap + height <= container.height - 12
        let fitsAbove = anchor.minY - gap - height >= 12
        let y = fitsBelow ? anchor.maxY + gap
            : (fitsAbove ? anchor.minY - gap - height : max(container.height - height - 12, 12))
        let unitX: CGFloat = payload.message.isOutgoing ? 1 : 0
        let growsFrom = UnitPoint(x: unitX, y: fitsBelow ? 0 : 1)

        DMMessageMenuCard(payload: payload, mode: manager.mode)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("AppWindow"))
            } action: { frame in
                manager.cardFrame = frame
                if manager.cardSize != frame.size { manager.cardSize = frame.size }
            }
            .position(x: x + width / 2, y: y + height / 2)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.86, anchor: growsFrom).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: growsFrom).combined(with: .opacity)
                )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: manager.mode)
    }
}

// MARK: - Card

private struct DMMessageMenuCard: View {
    let payload: DMMessageMenuPayload
    let mode: DMMessageMenuMode

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var vm = DMViewModel.shared

    @StateObject private var emojiCatcher = DMEmojiCatcher()

    private var message: DMMessage { payload.message }
    private var menu: DMMessageMenuManager { DMMessageMenuManager.shared }

    private var copyableText: String? {
        guard !message.isEncrypted else { return nil }
        if !message.text.isEmpty { return message.text }
        if let media = message.mediaUrl, !media.isEmpty { return media }
        return nil
    }

    private var myReaction: String? {
        let me = AccountManager.shared.activeId
        return payload.reactions.first { $0.senderId == me }?.emoji
    }

    private var iconColor: Color {
        theme.isLight ? ThemeManager.primaryText.opacity(0.85) : .white.opacity(0.90)
    }

    var body: some View {
        Group {
            switch mode {
            case .actions: actions
            case .info: DMMessageInfoView(message: message, reactions: payload.reactions)
            case .forward: forwardList
            case .delete: deleteChoices
            }
        }
        .transition(.opacity)
        .padding(5)
        .background { FloatingMenuBackground() }
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    // MARK: Actions

    private var actions: some View {
        let supported = vm.supportsActions(message)
        return VStack(alignment: .leading, spacing: 2) {
            if supported {
                reactionRow
                separator
                MenuRowButton(title: loc.t("messages_menu_reply"), icon: "arrowshape.turn.up.left", iconColor: iconColor, isDestructive: false) {
                    menu.dismiss()
                    vm.startReply(to: message)
                }
            }
            if let text = copyableText {
                MenuRowButton(title: loc.t("messages_menu_copy"), icon: "doc.on.doc", iconColor: iconColor, isDestructive: false) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    menu.dismiss()
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    AppToastManager.shared.show(loc.t("messages_copied"), icon: "checkmark.circle.fill")
                }
            }
            if supported && !message.text.isEmpty {
                MenuRowButton(title: loc.t("messages_menu_forward"), icon: "arrowshape.turn.up.right", iconColor: iconColor, isDestructive: false) {
                    menu.mode = .forward
                }
            }
            MenuRowButton(title: loc.t("messages_menu_info"), icon: "info.circle", iconColor: iconColor, isDestructive: false) {
                menu.mode = .info
            }
            if supported {
                separator
                MenuRowButton(title: loc.t("messages_menu_delete"), icon: "trash", iconColor: iconColor, isDestructive: true) {
                    menu.mode = .delete
                }
            }
        }
    }

    private var reactionRow: some View {
        HStack(spacing: 2) {
            ForEach(DMRecentReactions.row(including: myReaction), id: \.self) { emoji in
                DMQuickReactionButton(emoji: emoji) {
                    react(emoji)
                }
            }
            DMMoreReactionsButton {
                emojiCatcher.open { emoji in
                    react(emoji)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .background(DMEmojiCatcherView(catcher: emojiCatcher))
    }

    private func react(_ emoji: String) {
        let current = myReaction
        menu.dismiss()
        if current != emoji { DMRecentReactions.record(emoji) }
        vm.toggleReaction(emoji, on: message, current: current)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: Forward

    private var forwardList: some View {
        let targets = vm.forwardTargets(excluding: message.conversationId)
        return VStack(alignment: .leading, spacing: 2) {
            Text(loc.t("messages_forward_title"))
                .font(theme.appFont(size: 11, weight: .semibold))
                .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 2)
            if targets.isEmpty {
                Text(loc.t("messages_forward_empty"))
                    .font(theme.appFont(size: 12.5, weight: .regular))
                    .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55))
                    .padding(10)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(targets) { conv in
                            DMForwardTargetRow(conversation: conv) {
                                menu.dismiss()
                                vm.forward(message, to: conv.id)
                            }
                        }
                    }
                }
                // A scroll view in a card that sizes itself to its content needs a height of its own.
                .frame(height: min(CGFloat(targets.count) * 36, 280))
            }
        }
    }

    // MARK: Delete

    private var deleteChoices: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRowButton(title: loc.t("messages_delete_for_me"), icon: "trash", iconColor: iconColor, isDestructive: true) {
                menu.dismiss()
                vm.delete(message, forEveryone: false)
            }
            // Only the author can take a message back from everyone.
            if message.isOutgoing {
                MenuRowButton(title: loc.t("messages_delete_for_everyone"), icon: "trash.slash", iconColor: iconColor, isDestructive: true) {
                    menu.dismiss()
                    vm.delete(message, forEveryone: true)
                }
            }
            separator
            MenuRowButton(title: loc.t("messages_cancel"), icon: "xmark", iconColor: iconColor, isDestructive: false) {
                menu.mode = .actions
            }
        }
    }
}

private final class DMHoverFlag: ObservableObject {
    @Published var isHovered = false
}

/// One emoji in the reaction row.
private struct DMQuickReactionButton: View {
    let emoji: String
    let action: () -> Void

    @StateObject private var hover = DMHoverFlag()

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 19))
                .frame(width: 30, height: 30)
                .scaleEffect(hover.isHovered ? 1.22 : 1.0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.target)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: hover.isHovered)
        .onHover { hover.isHovered = $0 }
    }
}

/// The small arrow after the reactions, which opens the system's Emoji & Symbols panel.
private struct DMMoreReactionsButton: View {
    let action: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var hover = DMHoverFlag()

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.65))
                .frame(width: 24, height: 30)
                .background(
                    Circle()
                        .fill(hover.isHovered ? (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12)) : Color.clear)
                        .frame(width: 24, height: 24)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.target)
        .help(loc.t("messages_more_reactions"))
        .onHover { hover.isHovered = $0 }
    }
}

/// A conversation in the forward list.
private struct DMForwardTargetRow: View {
    let conversation: DMConversation
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var hover = DMHoverFlag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DMAvatarView(url: conversation.avatarUrl, size: 24)
                Text(conversation.displayName)
                    .font(theme.appFont(size: 13, weight: .regular))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hover.isHovered ? (theme.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12)) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.target)
        .onHover { hover.isHovered = $0 }
    }
}

// MARK: - Info

private struct DMMessageInfoView: View {
    let message: DMMessage
    let reactions: [DMMessage]

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var vm = DMViewModel.shared

    private var participants: [DMParticipant] {
        vm.conversations.first { $0.id == message.conversationId }?.participants ?? []
    }

    /// The sender as the conversation knows them, or the signed-in account for a message of one's own.
    private func person(_ id: String) -> DMParticipant? {
        if let p = participants.first(where: { $0.id == id }) { return p }
        if let acc = AccountManager.shared.accounts.first(where: { $0.id == id }) {
            return DMParticipant(id: acc.id, name: acc.name, screenName: acc.screenName, avatarUrl: acc.avatarUrl)
        }
        return nil
    }

    private var conversationEntries: [DMMessage] {
        vm.messagesByConv[message.conversationId] ?? []
    }
    
    private var seen: [(reader: String, at: Date)] {
        DMSeen.seenTimes(for: message, among: conversationEntries, receipts: vm.session.receipts)
            .map { ($0.key, $0.value) }
            .sorted { $0.at < $1.at }
    }

    private var secondaryColor: Color {
        theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.55)
    }

    private var primaryColor: Color {
        theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.94)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            senderHeader
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 9)

            separator

            VStack(alignment: .leading, spacing: 7) {
                statusRow(
                    icon: message.isOutgoing ? "paperplane" : "tray.and.arrow.down",
                    title: loc.t(message.isOutgoing ? "messages_info_sent" : "messages_info_received"),
                    detail: Self.format(message.createdAt, language: loc.currentLanguage)
                )
                if let editedAt = message.editedAt {
                    statusRow(icon: "pencil", title: loc.t("messages_info_edited"), detail: Self.format(editedAt, language: loc.currentLanguage))
                }
                if message.isOutgoing {
                    let seen = seen
                    // In a group, each reader gets a row of their own; in a one-to-one chat the reader is obvious.
                    let named = Set(seen.map(\.reader)).count > 1
                    ForEach(seen, id: \.reader) { entry in
                        let title = named
                            ? loc.format("messages_info_seen_by", ["name": person(entry.reader)?.name ?? ""])
                            : loc.t("messages_info_seen")
                        statusRow(icon: "eye", title: title, detail: Self.format(entry.at, language: loc.currentLanguage))
                    }
                    // Only claim "not seen" once receipts are known to be arriving for this conversation.
                    if seen.isEmpty && DMSeen.hasReceipts(in: message.conversationId, excluding: message.senderId, among: conversationEntries, receipts: vm.session.receipts) {
                        statusRow(icon: "eye.slash", title: loc.t("messages_info_not_seen"), detail: nil)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            if !reactions.isEmpty {
                separator
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.t("messages_info_reactions"))
                        .font(theme.appFont(size: 11, weight: .semibold))
                        .foregroundColor(secondaryColor)
                    ForEach(reactions) { reaction in
                        HStack(spacing: 8) {
                            Text(reaction.emoji ?? "")
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(person(reaction.senderId)?.name ?? "")
                                .font(theme.appFont(size: 12.5, weight: .regular))
                                .foregroundColor(primaryColor)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
        }
    }

    private var senderHeader: some View {
        let sender = person(message.senderId)
        return HStack(spacing: 9) {
            DMAvatarView(url: sender?.highResAvatarUrl ?? sender?.avatarUrl, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(sender?.name ?? message.senderId)
                        .font(theme.appFont(size: 13, weight: .semibold))
                        .foregroundColor(primaryColor)
                        .lineLimit(1)
                    if sender?.isBlueVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(hex: "#1D9BF0"))
                    }
                }
                if let handle = sender?.formattedHandle {
                    Text(handle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(secondaryColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, 6)
    }

    private func statusRow(icon: String, title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(secondaryColor)
                .frame(width: 16)
            Text(title)
                .font(theme.appFont(size: 12.5, weight: .medium))
                .foregroundColor(primaryColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(theme.appFont(size: 12, weight: .regular))
                    .foregroundColor(secondaryColor)
                    .lineLimit(1)
            }
        }
    }

    /// "Today, 9:41" style dates in the app's chosen language rather than the system's.
    private static func format(_ date: Date, language: AppLanguage) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: language.rawValue)
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        fmt.doesRelativeDateFormatting = true
        return fmt.string(from: date)
    }
}
