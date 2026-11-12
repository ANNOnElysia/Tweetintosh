//
//  PressDragSelection.swift
//  Tweetintosh - Headless Data-driven Client
//
// The bar owns the gesture so a press can move between items. With a preview binding, the highlight stays on the
// group's axis and within its item bounds until release commits the destination.
//

import SwiftUI
import AppKit

struct PressDragPreview<ID: Hashable>: Equatable {
    let sourceID: ID
    let id: ID
    let translation: CGSize
    let size: CGSize

    init?(sourceID: ID, translation: CGSize, axis: Axis, frames: [AnyHashable: CGRect]) {
        guard let source = frames[AnyHashable(sourceID)] else { return nil }
        let sourceCenter = axis == .horizontal ? source.midX : source.midY
        let position = sourceCenter + (axis == .horizontal ? translation.width : translation.height)
        var before: (id: AnyHashable, frame: CGRect, center: CGFloat)?
        var after: (id: AnyHashable, frame: CGRect, center: CGFloat)?
        for (id, frame) in frames {
            let center = axis == .horizontal ? frame.midX : frame.midY
            if center <= position, before == nil || center > before!.center { before = (id, frame, center) }
            if center >= position, after == nil || center < after!.center { after = (id, frame, center) }
        }
        guard let first = before ?? after, let second = after ?? before else { return nil }
        let distance = second.center - first.center
        let progress = distance > 0 ? min(1, max(0, (position - first.center) / distance)) : 0
        guard let destination = (progress < 0.5 ? first.id : second.id).base as? ID else { return nil }
        self.sourceID = sourceID
        self.id = destination
        let center = first.center + distance * progress
        self.translation = axis == .horizontal
            ? CGSize(width: center - sourceCenter, height: 0)
            : CGSize(width: 0, height: center - sourceCenter)
        self.size = CGSize(
            width: first.frame.width + (second.frame.width - first.frame.width) * progress,
            height: first.frame.height + (second.frame.height - first.frame.height) * progress
        )
    }
}

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
    var bounds: CGRect = .zero
    var current: AnyHashable?
    var isDragging = false
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
    let preview: Binding<PressDragPreview<ID>?>?
    let axis: Axis
    let onSelect: (ID) -> Void
    @StateObject private var state = PressDragState()
    @GestureState private var isTracking = false

    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(PressDragItemFramesKey.self) { anchors in
                GeometryReader { geometry in
                    let _ = (state.frames = anchors.mapValues { geometry[$0] })
                    let _ = (state.bounds = CGRect(origin: .zero, size: geometry.size))
                    Color.clear
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($isTracking) { _, tracking, _ in tracking = true }
                    .onChanged { value in
                        if let preview {
                            // Layout preferences can be transiently unavailable without ending the press.
                            guard let next = trackedPreview(value) else { return }
                            withTransaction(Transaction(animation: nil)) {
                                preview.wrappedValue = next
                            }
                        } else {
                            track(value.location)
                        }
                    }
                    .onEnded { value in
                        if preview != nil, state.bounds.contains(value.location), let destination = trackedPreview(value) {
                            onSelect(destination.id)
                        }
                        reset()
                    }
            )
            // Gesture state also resets when SwiftUI cancels the drag without calling onEnded.
            .onChange(of: isTracking) { _, tracking in
                if !tracking { reset() }
            }
            .onDisappear { reset() }
            .environment(\.pressDragSelect) { id in
                if let id = id.base as? ID {
                    onSelect(id)
                }
            }
    }

    private func trackedPreview(_ value: DragGesture.Value) -> PressDragPreview<ID>? {
        guard let preview,
              let source = preview.wrappedValue?.sourceID ?? (item(at: value.startLocation)?.base as? ID) else { return nil }
        var translation = value.translation
        if !state.isDragging {
            let distance = axis == .horizontal ? translation.width : translation.height
            if abs(distance) < 3 {
                translation = .zero
            } else {
                state.isDragging = true
            }
        }
        return PressDragPreview(sourceID: source, translation: translation, axis: axis, frames: state.frames)
    }

    private func track(_ point: CGPoint) {
        let nearest = item(at: point)
        guard nearest != state.current else { return }
        let isDragAcross = state.current != nil
        state.current = nearest
        let id = nearest?.base as? ID
        if let id { onSelect(id) }
        if isDragAcross, id != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func item(at point: CGPoint) -> AnyHashable? {
        // Leaving the padded hit area cancels a deferred selection instead of choosing a distant end tab.
        guard preview == nil || state.bounds.contains(point) else { return nil }
        return state.frames.min {
            Self.distance(from: point, to: $0.value) < Self.distance(from: point, to: $1.value)
        }?.key
    }

    private func reset() {
        state.current = nil
        state.isDragging = false
        preview?.wrappedValue = nil
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }
}

private struct PressDragSelectionSurface<ID: Hashable, Surface: View>: ViewModifier {
    let selection: ID?
    let preview: PressDragPreview<ID>?
    let surface: () -> Surface

    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(PressDragItemFramesKey.self) { anchors in
                GeometryReader { geometry in
                    if let frame = selectionFrame(geometry: geometry, anchors: anchors) {
                        surface()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    private func selectionFrame(geometry: GeometryProxy, anchors: [AnyHashable: Anchor<CGRect>]) -> CGRect? {
        guard let id = preview?.sourceID ?? selection, let anchor = anchors[AnyHashable(id)] else { return nil }
        let source = geometry[anchor]
        let translation = preview?.translation ?? .zero
        let size = preview?.size ?? source.size
        return CGRect(x: source.midX + translation.width - size.width / 2,
                      y: source.midY + translation.height - size.height / 2,
                      width: size.width, height: size.height)
    }
}

extension View {
    // On each item of the bar
    func pressDragItem<ID: Hashable>(_ id: ID) -> some View {
        modifier(PressDragItem(id: id))
    }

    // On the row holding the items
    func pressDragSelection<ID: Hashable>(preview: Binding<PressDragPreview<ID>?>? = nil, axis: Axis = .horizontal,
                                          onSelect: @escaping (ID) -> Void) -> some View {
        modifier(PressDragSelection(preview: preview, axis: axis, onSelect: onSelect))
    }

    // The shared native surface stays behind the controls and never captures input.
    func pressDragSelectionSurface<ID: Hashable, Surface: View>(
        selection: ID?, preview: PressDragPreview<ID>?,
        @ViewBuilder surface: @escaping () -> Surface
    ) -> some View {
        modifier(PressDragSelectionSurface(
            selection: selection, preview: preview, surface: surface
        ))
    }
}
