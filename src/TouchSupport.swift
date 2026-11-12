//
//  TouchSupport.swift
//  Tweetintosh - Headless Data-driven Client
//
//  Adjustments for touch screens (macOS 27): a finger needs scrolling that stays under it, a pull to refresh measured
//  for a finger's travel, and targets big enough to hit.
//

import AppKit
import SwiftUI

// Which input is driving the scroll in progress. A finger on the screen scrolls without sending any scroll-wheel events,
// and event monitors never see a direct touch, so a live scroll that begins with no scroll-wheel event just before it is
// taken to be a finger. Dragging a scroller's thumb is caught the same way, which suits it: it too should follow the
// pointer exactly, with nothing tuned for a trackpad flick applied.
final class ScrollInput {
    static let shared = ScrollInput()

    private(set) var isDirectTouch = false
    private var lastWheelEventAt: CFTimeInterval = 0
    private var monitor: Any?
    private var observer: NSObjectProtocol?

    func start() {
        guard monitor == nil else { return }
        // A monitor runs before the event reaches the scroll view, so the time is set before the live scroll begins
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.lastWheelEventAt = CACurrentMediaTime()
            return event
        }
        // No queue: delivered at once on the main thread, before the first step of the scroll is taken
        observer = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.isDirectTouch = CACurrentMediaTime() - self.lastWheelEventAt > 0.15
        }
    }
}

// Dragging the window by any empty part of it is handy with a pointer and a trap for a finger, which always moves a
// little while it is down: a tap on a glass bar or beside a control starts moving the window instead, and the control
// never sees it. So while a touch screen is connected the window moves only by its title bar.
enum WindowDragging {
    private static weak var window: NSWindow?
    private static var isScrolling = false
    private static var observer: NSObjectProtocol?

    static func keepUpdated(_ window: NSWindow) {
        self.window = window
        update(window)
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak window] _ in
            if let window { update(window) }
        }
    }

    // While content is moving, AppKit walks the SwiftUI view tree on every scroll step to find regions that can start
    // a window drag. That walk costs a noticeable part of a scrolling frame. Dragging stays available from the title
    // bar, and normal background behaviour returns as soon as scrolling stops.
    static func setScrolling(_ scrolling: Bool) {
        guard scrolling != isScrolling else { return }
        isScrolling = scrolling
        if let window { update(window) }
    }

    private static func update(_ window: NSWindow) {
        window.isMovableByWindowBackground = !hasTouchScreen && !isScrolling
    }

    private static var hasTouchScreen: Bool {
        guard #available(macOS 27.0, *) else { return false }
        return NSScreen.screens.contains { $0.touchCapabilities.contains(.multiTouch) }
    }
}

// The app's plain button: the system's plain style, taking clicks and taps over a rectangle at least 36 points each way
// (Apple's touch target on the Mac), however small its label, and over the whole of the label's frame, gaps between an
// icon and its count included. A plain button only answers inside its own frame, so the frame itself grows, and padding
// outside the button takes the growth back, leaving the layout as it was. Every borderless button in the app uses it.
struct TargetButtonStyle: PrimitiveButtonStyle {
    static let minimum: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        TargetButton(configuration: configuration)
    }
}

private struct TargetButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @State private var labelSize: CGSize = .zero

    var body: some View {
        let dx = max(0, (TargetButtonStyle.minimum - labelSize.width) / 2)
        let dy = max(0, (TargetButtonStyle.minimum - labelSize.height) / 2)
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .onGeometryChange(for: CGSize.self) { $0.size } action: { labelSize = $0 }
                .padding(.horizontal, dx)
                .padding(.vertical, dy)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -dx)
        .padding(.vertical, -dy)
    }
}

extension PrimitiveButtonStyle where Self == TargetButtonStyle {
    static var target: TargetButtonStyle { TargetButtonStyle() }
}

extension View {
    // A pointing hand belongs to content that opens a post, a profile or another page, so a row that navigates shows
    // the extent of its hit area before the click lands. Actions, menus and tabs keep the arrow, as standard macOS
    // controls do; Apple defines this hand as the pointer for links and other opened items.
    // Pass false where the row currently opens nothing, so a preview doesn't claim an action it won't take. It only
    // withholds the hand: a subview's own pointer style, such as a link inside the row, still applies.
    func navigationPointer(_ isActive: Bool = true) -> some View {
        // Keep the hover receiver alive when the cursor changes; switching view branches replaces it mid-hover.
        pointerStyle(isActive ? .link : nil)
    }
}
