//
//  DMSwipeActions.swift
//  Tweetintosh
//
//  macOS Messages-style horizontal swipe actions for DM conversation rows.
//  Matches macOS Messages physics: staggered bloom from zero, velocity-aware snap,
//  and continuous outer-pill stretch with dimmed inner button on full swipe.
//

import AppKit
import SwiftUI

// MARK: - Action Presentation

struct DMSwipeActionInfo {
    let icon: String
    let color: Color
    let title: String
}

extension DMSwipeAction {
    func presentation(for conversation: DMConversation, isMuted: Bool, loc: LocalizationManager) -> DMSwipeActionInfo {
        switch self {
        case .toggleRead:
            let isUnread = conversation.unreadCount > 0
            return DMSwipeActionInfo(
                icon: isUnread ? "envelope.open.fill" : "envelope.badge.fill",
                color: ThemeManager.accent,
                title: loc.t(isUnread ? "messages_mark_read" : "messages_mark_unread")
            )
        case .pin:
            return DMSwipeActionInfo(
                icon: conversation.isPinned ? "pin.slash.fill" : "pin.fill",
                color: .orange,
                title: loc.t(conversation.isPinned ? "messages_unpin" : "messages_pin")
            )
        case .mute:
            return DMSwipeActionInfo(
                icon: isMuted ? "bell.fill" : "bell.slash.fill",
                color: Color(red: 0.35, green: 0.34, blue: 0.84),
                title: loc.t(isMuted ? "messages_unmute" : "messages_mute")
            )
        case .delete:
            return DMSwipeActionInfo(
                icon: "trash.fill",
                color: .red,
                title: loc.t("messages_delete")
            )
        }
    }
}

// MARK: - Shared Trackpad Swipe Coordinator

/// Routes two-finger horizontal trackpad scroll gestures on DM rows to the row under the pointer,
/// while letting vertical scroll gestures pass through to the enclosing ScrollView.
final class DMRowSwipeCoordinator {
    static let shared = DMRowSwipeCoordinator()

    private enum Axis {
        case none
        case horizontal
        case vertical
    }

    private final class Registration {
        weak var view: NSView?
        var isEnabled: () -> Bool
        var onBegan: () -> Void
        var onDelta: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void

        init(
            view: NSView,
            isEnabled: @escaping () -> Bool,
            onBegan: @escaping () -> Void,
            onDelta: @escaping (CGFloat) -> Void,
            onEnded: @escaping (CGFloat) -> Void
        ) {
            self.view = view
            self.isEnabled = isEnabled
            self.onBegan = onBegan
            self.onDelta = onDelta
            self.onEnded = onEnded
        }
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]
    private var monitor: Any?
    private var activeId: ObjectIdentifier?
    private var lockedAxis: Axis = .none
    private var lastDeltaX: CGFloat = 0
    private var dismissOpenSwipe: (() -> Void)?

    private init() {}

    func register(
        view: NSView,
        isEnabled: @escaping () -> Bool,
        dismissOpenSwipe: @escaping () -> Void,
        onBegan: @escaping () -> Void,
        onDelta: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat) -> Void
    ) {
        let key = ObjectIdentifier(view)
        registrations[key] = Registration(
            view: view,
            isEnabled: isEnabled,
            onBegan: onBegan,
            onDelta: onDelta,
            onEnded: onEnded
        )
        self.dismissOpenSwipe = dismissOpenSwipe
        ensureMonitor()
    }

    func unregister(view: NSView) {
        let key = ObjectIdentifier(view)
        registrations.removeValue(forKey: key)
        if activeId == key {
            activeId = nil
            lockedAxis = .none
        }
        if registrations.isEmpty, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func ensureMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas else { return event }

        let isBegin = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        if isBegin {
            lockedAxis = .none
            lastDeltaX = 0
            activeId = hitRegistration(for: event)
        }

        if registrations.values.contains(where: { $0.view == nil }) {
            registrations = registrations.filter { $0.value.view != nil }
        }

        guard let activeId, let reg = registrations[activeId], reg.isEnabled() else {
            if isBegin {
                activeId = nil
                lockedAxis = .none
            }
            return event
        }

        if lockedAxis == .none {
            let dx = abs(event.scrollingDeltaX)
            let dy = abs(event.scrollingDeltaY)
            if dx > 0.1 || dy > 0.1 {
                if dx > dy {
                    lockedAxis = .horizontal
                    reg.onBegan()
                    if event.momentumPhase.isEmpty {
                        lastDeltaX = event.scrollingDeltaX
                        reg.onDelta(event.scrollingDeltaX)
                    }
                    return nil
                } else {
                    lockedAxis = .vertical
                    dismissOpenSwipe?()
                    return event
                }
            }
            return event
        }

        switch lockedAxis {
        case .none, .vertical:
            return event
        case .horizontal:
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                reg.onEnded(lastDeltaX)
                self.activeId = nil
                self.lockedAxis = .none
                self.lastDeltaX = 0
                return nil
            }
            if event.momentumPhase.isEmpty {
                if abs(event.scrollingDeltaX) > 0.05 {
                    lastDeltaX = event.scrollingDeltaX
                }
                reg.onDelta(event.scrollingDeltaX)
            }
            return nil
        }
    }

    private func hitRegistration(for event: NSEvent) -> ObjectIdentifier? {
        guard let window = event.window else { return nil }
        let location = event.locationInWindow
        for (key, reg) in registrations {
            guard let view = reg.view, view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
            let rectInWindow = view.convert(view.bounds, to: nil)
            if rectInWindow.contains(location) {
                return key
            }
        }
        return nil
    }
}

private struct DMRowSwipeMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let dismissOpenSwipe: () -> Void
    let onBegan: () -> Void
    let onDelta: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    final class Coordinator {
        var view: NSView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        DMRowSwipeCoordinator.shared.register(
            view: view,
            isEnabled: { isEnabled },
            dismissOpenSwipe: dismissOpenSwipe,
            onBegan: onBegan,
            onDelta: onDelta,
            onEnded: onEnded
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DMRowSwipeCoordinator.shared.register(
            view: nsView,
            isEnabled: { isEnabled },
            dismissOpenSwipe: dismissOpenSwipe,
            onBegan: onBegan,
            onDelta: onDelta,
            onEnded: onEnded
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        DMRowSwipeCoordinator.shared.unregister(view: nsView)
    }
}

// MARK: - Swipeable Row Wrapper

struct DMSwipeableRow<Content: View>: View {
    let conversation: DMConversation
    let isEditMode: Bool
    @ObservedObject var vm: DMViewModel
    @ObservedObject var theme: ThemeManager
    @ObservedObject var loc: LocalizationManager
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?
    @State private var isSwiping = false
    @State private var didTriggerFullSwipeHaptic = false

    private let buttonSize: CGFloat = 38
    private let buttonSpacing: CGFloat = 8
    private let trailingPadding: CGFloat = 8
    private var openOffset: CGFloat { buttonSize * 2 + buttonSpacing + trailingPadding + 6 }
    private let fullSwipeThreshold: CGFloat = 200
    private let maxSwipeDistance: CGFloat = 260

    private var isOpen: Bool {
        vm.activeSwipeConversationId == conversation.id
    }

    private var effectiveOffset: CGFloat {
        guard !isEditMode else { return 0 }
        if isSwiping { return dragOffset }
        return isOpen ? -openOffset : 0
    }

    private var isFullSwipe: Bool {
        (-effectiveOffset) >= fullSwipeThreshold
    }

    private var isOuterVisible: Bool {
        (-effectiveOffset) >= 38
    }

    private var isInnerVisible: Bool {
        (-effectiveOffset) >= 72
    }

    var body: some View {
        let isMuted = vm.mutedConversationIds.contains(conversation.id)
        let innerInfo = theme.dmSwipeInnerAction.presentation(for: conversation, isMuted: isMuted, loc: loc)
        let outerInfo = theme.dmSwipeOuterAction.presentation(for: conversation, isMuted: isMuted, loc: loc)

        ZStack(alignment: .trailing) {
            if effectiveOffset < -1 {
                swipeTray(innerInfo: innerInfo, outerInfo: outerInfo)
                    .padding(.trailing, trailingPadding)
                    .padding(.vertical, 6)
                    .frame(width: max(0, -effectiveOffset), alignment: .trailing)
                    .clipped()
                    .zIndex(0)
            }

            content()
                .offset(x: effectiveOffset)
                .animation(isSwiping ? nil : .spring(response: 0.36, dampingFraction: 0.68), value: effectiveOffset)
                .zIndex(1)
        }
        .clipped()
        .background(
            DMRowSwipeMonitor(
                isEnabled: !isEditMode,
                dismissOpenSwipe: {
                    if vm.activeSwipeConversationId != nil {
                        vm.activeSwipeConversationId = nil
                    }
                },
                onBegan: { beginSwipe() },
                onDelta: { delta in updateSwipe(delta: delta) },
                onEnded: { lastDelta in endSwipe(velocityX: lastDelta) }
            )
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    guard !isEditMode else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if dragStartOffset == nil {
                        dragStartOffset = isOpen ? -openOffset : 0
                        beginSwipe()
                    }
                    let base = dragStartOffset ?? 0
                    setOffset(base + value.translation.width)
                }
                .onEnded { value in
                    guard dragStartOffset != nil else { return }
                    dragStartOffset = nil
                    let predictedDelta = value.predictedEndTranslation.width - value.translation.width
                    endSwipe(velocityX: predictedDelta * 0.08)
                }
        )
        .onChange(of: isEditMode) { _, editing in
            if editing && isOpen {
                vm.activeSwipeConversationId = nil
            }
        }
    }

    @ViewBuilder
    private func swipeTray(innerInfo: DMSwipeActionInfo, outerInfo: DMSwipeActionInfo) -> some View {
        let absOffset = max(0, -effectiveOffset)
        // Once past openOffset, the outer pill stretches continuously into a capsule
        let extraStretch = max(0, absOffset - openOffset)
        let outerWidth = buttonSize + extraStretch * 0.92
        let isStretched = outerWidth > buttonSize + 10

        HStack(spacing: buttonSpacing) {
            Button(action: { trigger(theme.dmSwipeInnerAction) }) {
                Image(systemName: innerInfo.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(innerInfo.color))
            }
            .buttonStyle(.plain)
            .help(innerInfo.title)
            .scaleEffect(isInnerVisible ? 1.0 : 0.01)
            .opacity(isInnerVisible ? (isFullSwipe ? 0.35 : 1.0) : 0.0)
            .allowsHitTesting(isInnerVisible)
            .animation(.spring(response: 0.34, dampingFraction: 0.56), value: isInnerVisible)
            .animation(.easeOut(duration: 0.16), value: isFullSwipe)

            Button(action: { trigger(theme.dmSwipeOuterAction) }) {
                ZStack {
                    Capsule()
                        .fill(outerInfo.color)
                    Image(systemName: outerInfo.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: isStretched ? .leading : .center)
                        .padding(.leading, isStretched ? 12 : 0)
                }
                .frame(width: outerWidth, height: buttonSize)
            }
            .buttonStyle(.plain)
            .help(outerInfo.title)
            .scaleEffect(isOuterVisible ? 1.0 : 0.01)
            .opacity(isOuterVisible ? 1.0 : 0.0)
            .allowsHitTesting(isOuterVisible)
            .animation(.spring(response: 0.34, dampingFraction: 0.56), value: isOuterVisible)
        }
    }

    private func beginSwipe() {
        if vm.activeSwipeConversationId != nil && vm.activeSwipeConversationId != conversation.id {
            vm.activeSwipeConversationId = nil
        }
        dragOffset = isOpen ? -openOffset : 0
        didTriggerFullSwipeHaptic = (-dragOffset) >= fullSwipeThreshold
        isSwiping = true
    }

    private func updateSwipe(delta: CGFloat) {
        if !isSwiping { beginSwipe() }
        setOffset(dragOffset + delta)
    }

    private func setOffset(_ proposed: CGFloat) {
        let clamped = min(0, max(-maxSwipeDistance, proposed))
        dragOffset = clamped

        let crossed = (-clamped) >= fullSwipeThreshold
        if crossed != didTriggerFullSwipeHaptic {
            didTriggerFullSwipeHaptic = crossed
            if crossed {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
        }
    }

    private func endSwipe(velocityX: CGFloat) {
        let finalOffset = dragOffset
        isSwiping = false
        didTriggerFullSwipeHaptic = false

        if (-finalOffset) >= fullSwipeThreshold {
            vm.activeSwipeConversationId = nil
            vm.performSwipeAction(theme.dmSwipeOuterAction, on: conversation)
        } else if velocityX < -2.2 && (-finalOffset) > 16 {
            vm.activeSwipeConversationId = conversation.id
        } else if velocityX > 2.2 {
            vm.activeSwipeConversationId = nil
        } else if (-finalOffset) >= openOffset * 0.42 {
            vm.activeSwipeConversationId = conversation.id
        } else {
            if isOpen {
                vm.activeSwipeConversationId = nil
            }
        }
        dragOffset = 0
    }

    private func trigger(_ action: DMSwipeAction) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
            vm.activeSwipeConversationId = nil
        }
        vm.performSwipeAction(action, on: conversation)
    }
}
