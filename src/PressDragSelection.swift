//
//  PressDragSelection.swift
//  Tweetintosh - Headless Data-driven Client
//
//  For the capsule tab bars: an item is chosen the moment the pointer presses it, and dragging across the bar moves the
//  choice along with it, like sliding a finger along a control on iOS. Buttons can't do this, because they wait for the
//  release and keep the press to themselves, so the items are plain views and the bar as a whole takes the gesture.
//

import SwiftUI
import AppKit

private struct PressDragItemFramesKey: PreferenceKey {
    static let defaultValue: [AnyHashable: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct PressDragSelectKey: EnvironmentKey {
    static let defaultValue: (AnyHashable) -> Void = { _ in }
}

private extension EnvironmentValues {
    var pressDragSelect: (AnyHashable) -> Void {
        get { self[PressDragSelectKey.self] }
        set { self[PressDragSelectKey.self] = newValue }
    }
}

// Not published: the frames change as the bar animates, and nothing draws from them
private final class PressDragState: ObservableObject {
    var frames: [AnyHashable: CGRect] = [:]
    var current: AnyHashable?
}

private struct PressDragItem<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.pressDragSelect) private var select

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: PressDragItemFramesKey.self, value: .bounds) { [AnyHashable(id): $0] }
            // Still a button to VoiceOver, which can't press and drag
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select(AnyHashable(id)) }
    }
}

private struct PressDragSelection<ID: Hashable>: ViewModifier {
    let onSelect: (ID) -> Void
    @StateObject private var state = PressDragState()

    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(PressDragItemFramesKey.self) { anchors in
                GeometryReader { geometry in
                    let _ = (state.frames = anchors.mapValues { geometry[$0] })
                    Color.clear
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { track($0.location) }
                    .onEnded { _ in state.current = nil }
            )
            .environment(\.pressDragSelect) { id in
                if let id = id.base as? ID { onSelect(id) }
            }
    }

    private func track(_ point: CGPoint) {
        // The nearest item, so the choice stays at the end of the bar when the pointer runs past it
        let nearest = state.frames.min { Self.distance(from: point, to: $0.value) < Self.distance(from: point, to: $1.value) }?.key
        guard let nearest = nearest, nearest != state.current, let id = nearest.base as? ID else { return }
        let isDragAcross = state.current != nil
        state.current = nearest
        if isDragAcross {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        onSelect(id)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }
}

extension View {
    // On each item of the bar
    func pressDragItem<ID: Hashable>(_ id: ID) -> some View {
        modifier(PressDragItem(id: id))
    }

    // On the row holding the items
    func pressDragSelection<ID: Hashable>(onSelect: @escaping (ID) -> Void) -> some View {
        modifier(PressDragSelection(onSelect: onSelect))
    }
}
