//
//  FrameAnchor.swift
//  Tweetintosh
//
//  Finds where a view is in window space when it is tapped, without measuring it while scrolling.
//

import SwiftUI
import AppKit

// MARK: - Window-space Frame Holder
// Knows how to find where something is; read only when it is tapped, so scrolling does no work for it.
final class FrameBox: ObservableObject {
    // Outside a table cell: an AppKit view that marks the spot
    weak var view: NSView?
    // Inside one: the position relative to the cell, and the cell's hosting view to convert it
    fileprivate weak var cell: TableCellGeometry?
    fileprivate var cellFrame: CGRect = .zero

    // Where it really is, in the "AppWindow" space: read from AppKit, so it is right however a table has scrolled
    var liveRect: CGRect {
        guard let now = currentWindowRect(), let origin = AppWindowOrigin.windowRect else { return .zero }
        return CGRect(x: now.minX - origin.minX, y: origin.maxY - now.maxY, width: now.width, height: now.height)
    }

    private func currentWindowRect() -> CGRect? {
        if let host = cell?.hostView, host.window != nil { return host.convert(cellFrame, to: nil) }
        guard let view = view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }
}

// Lets a FrameBox find this view, in whichever way suits where the view is
struct LocatesFrame: ViewModifier {
    let box: FrameBox
    @Environment(\.tableCellGeometry) private var cell

    func body(content: Content) -> some View {
        if let cell = cell {
            content.onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(TableCellGeometry.spaceName))
            } action: { [box] frame in
                box.cell = cell
                box.cellFrame = frame
            }
        } else {
            content.background(FrameAnchor(box: box))
        }
    }
}

// The "AppWindow" coordinate space starts at the top-left of the root view; this finds where that is on screen
enum AppWindowOrigin {
    fileprivate static weak var view: NSView?

    static var windowRect: CGRect? {
        guard let view = view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    // The window's size in "AppWindow" space, for clipping anything that runs past the edge
    static var bounds: CGRect? {
        guard let view = view, view.window != nil else { return nil }
        return CGRect(origin: .zero, size: view.bounds.size)
    }

    struct Anchor: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            AppWindowOrigin.view = view
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {
            AppWindowOrigin.view = view
        }
    }
}

struct FrameAnchor: NSViewRepresentable {
    let box: FrameBox
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}
