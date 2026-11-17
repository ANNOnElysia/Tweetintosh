//
//  HorizontalOnlyScrolling.swift
//  Tweetintosh
//
//  Keeps a horizontal carousel from taking the timeline's vertical scroll gestures.
//

import AppKit
import SwiftUI

// MARK: - Horizontal-only Scrolling
// A horizontal ScrollView nested in the timeline keeps hold of vertical scroll gestures that start over it, so
// once the images have been scrolled sideways the timeline stops following the trackpad. A gesture that starts out
// mostly vertical over such a scroll view is handed to the enclosing scroll view instead, for its whole length
// (momentum included). Done with an event monitor: SwiftUI observes its scroll views, so they can't be subclassed.
final class HorizontalOnlyScrolling {
    static let shared = HorizontalOnlyScrolling()

    private let carousels = NSHashTable<NSScrollView>.weakObjects()
    private var monitor: Any?
    // Where the gesture in progress is being redirected, if it is
    private weak var redirectTarget: NSScrollView?

    func register(_ scrollView: NSScrollView) {
        carousels.add(scrollView)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let startsGesture = event.phase.contains(.began) || event.phase.contains(.mayBegin)
            || (event.phase.isEmpty && event.momentumPhase.isEmpty)
        if startsGesture {
            redirectTarget = nil
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let carousel = carousel(under: event) {
                redirectTarget = carousel.enclosingScrollView
            }
        }
        guard let target = redirectTarget else { return event }
        target.scrollWheel(with: event)
        return nil
    }

    private func carousel(under event: NSEvent) -> NSScrollView? {
        guard let window = event.window, let content = window.contentView, let frameView = content.superview else { return nil }
        // Bounds first: a mouse wheel comes here on every tick, and a hit test goes through SwiftUI's hit testing of every
        // row on screen. It is still needed when the pointer is over a carousel, in case something covers it.
        let isOverCarousel = carousels.allObjects.contains {
            $0.window === window && $0.convert($0.bounds, to: nil).contains(event.locationInWindow)
        }
        guard isOverCarousel else { return nil }
        var view = content.hitTest(frameView.convert(event.locationInWindow, from: nil))
        while let current = view {
            if let scrollView = current as? NSScrollView, carousels.contains(scrollView) { return scrollView }
            view = current.superview
        }
        return nil
    }
}
