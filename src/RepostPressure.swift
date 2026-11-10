import AppKit
import SwiftUI

// A row's lifetime, geometry and action stay together when NSTableView reuses its hosting view.
final class RepostPressState: ObservableObject {
    fileprivate weak var cell: TableCellGeometry?
    fileprivate weak var anchor: NSView?
    fileprivate var frame: CGRect = .zero
    fileprivate var scope: PeekScope = .none
    fileprivate var tweetID = ""
    fileprivate var action: (() -> Void)?
    fileprivate var didForceClick = false

    func consumeClick() -> Bool {
        defer { didForceClick = false }
        return didForceClick && NSApp.currentEvent?.type == .leftMouseUp
    }

    fileprivate func contains(_ event: NSEvent) -> Bool {
        guard let host = cell?.hostView ?? anchor, host.window === event.window else { return false }
        let rect = cell == nil ? host.bounds : frame
        let dx = max(0, (TargetButtonStyle.minimum - rect.width) / 2)
        let dy = max(0, (TargetButtonStyle.minimum - rect.height) / 2)
        let target = rect.insetBy(dx: -dx, dy: -dy).intersection(host.visibleRect)
        return target.contains(host.convert(event.locationInWindow, from: nil))
    }
}

private final class RepostPressMonitor {
    static let shared = RepostPressMonitor()
    private let targets = NSHashTable<RepostPressState>.weakObjects()
    private var monitor: Any?
    private weak var pressed: RepostPressState?
    private var pressedID = ""

    func register(_ target: RepostPressState) {
        targets.add(target)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .pressure]) {
            [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            pressed = nil
            guard isAvailable(event) else { return event }
            let scope = PeekCoordinator.shared.activeScope()
            for case let target as RepostPressState in targets.objectEnumerator() {
                if target.scope == scope && target.contains(event) {
                    target.didForceClick = false
                    pressed = target
                    pressedID = target.tweetID
                    break
                }
            }
        case .pressure:
            guard event.stage >= 2, let target = pressed, !target.didForceClick,
                  target.tweetID == pressedID, isAvailable(event),
                  target.scope == PeekCoordinator.shared.activeScope(), target.contains(event) else { return event }
            // Mark the press before engagement redraws the row, and let mouse-up reach the button to clear its tracking.
            target.didForceClick = true
            target.action?()
            return nil
        case .leftMouseUp:
            pressed = nil
        default:
            break
        }
        return event
    }

    private func isAvailable(_ event: NSEvent) -> Bool {
        guard let window = event.window, window === NSApp.mainWindow, window.attachedSheet == nil else { return false }
        return PeekCoordinator.shared.target == nil && PeekCoordinator.shared.activeScope() != .none
    }
}

private final class RepostPressAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct RepostPressAnchor: NSViewRepresentable {
    let state: RepostPressState

    func makeNSView(context: Context) -> RepostPressAnchorView {
        let view = RepostPressAnchorView()
        state.anchor = view
        return view
    }

    func updateNSView(_ view: RepostPressAnchorView, context: Context) {
        state.anchor = view
    }
}

struct RepostPressureRegion: View {
    let state: RepostPressState
    let tweetID: String
    let action: () -> Void
    @Environment(\.tableCellGeometry) private var cell
    @Environment(\.peekScope) private var scope

    var body: some View {
        if cell !== TableCellGeometry.forMeasuring {
            region
        }
    }

    private var region: some View {
        state.cell = cell
        state.scope = scope
        state.tweetID = tweetID
        state.action = action
        RepostPressMonitor.shared.register(state)
        return Group {
            if cell != nil {
                Color.clear.onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(TableCellGeometry.spaceName))
                } action: { state.frame = $0 }
            } else {
                RepostPressAnchor(state: state)
            }
        }
        .allowsHitTesting(false)
    }
}
