//
//  LightboxState.swift
//  Tweetintosh
//
//  The photo viewer's state: thumbnail frames, presentation, zoom/pan and the keyboard/trackpad gestures.
//

import SwiftUI
import AppKit

// MARK: - Media Frame Registry (Tracks thumbnail coordinates in AppWindow space)
final class MediaFrameRegistry {
    static let shared = MediaFrameRegistry()
    private var frames: [String: CGRect] = [:]
    // Live providers win over stored frames: a List scrolls without SwiftUI re-reporting positions, so a frame
    // stored at open time (or last reported by SwiftUI) can be stale by the time the lightbox closes
    private var providers: [String: () -> CGRect?] = [:]
    private let lock = NSLock()

    private init() {}

    func register(key: String, frame: CGRect) {
        guard frame.width > 5, frame.height > 5 else { return }
        lock.lock()
        frames[key] = frame
        lock.unlock()
    }

    func register(key: String, provider: @escaping () -> CGRect?) {
        lock.lock()
        providers[key] = provider
        lock.unlock()
    }

    func frame(for key: String) -> CGRect? {
        lock.lock()
        let provider = providers[key]
        let stored = frames[key]
        lock.unlock()
        if let live = provider?(), live.width > 5, live.height > 5 { return live }
        return stored
    }

    func clear() {
        lock.lock()
        frames.removeAll()
        // Providers are registered by the tiles for one presentation too. Keeping them would leave a closure and key
        // for every picture ever opened; the next open registers its own before presenting.
        providers.removeAll()
        lock.unlock()
    }
}

// MARK: - Lightbox State Manager
final class LightboxManager: ObservableObject {
    static let shared = LightboxManager()

    @Published var isPresented: Bool = false
    @Published var mediaList: [TweetMedia] = []
    @Published var initialIndex: Int = 0
    @Published var currentIndex: Int = 0
    @Published var isAnimatingOut: Bool = false
    @Published var sourceRect: CGRect = .zero
    @Published var isZoomExpanded: Bool = false

    // Zoom & Pan State
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero
    @Published var maxPanLimit: CGSize = .zero
    var startPanOffset: CGSize = .zero
    @Published var isPanningZoom: Bool = false

    // Dismiss / Swipe Drag State
    @Published var dragOffset: CGSize = .zero
    @Published var isDraggingVertically: Bool = false
    @Published var isDraggingHorizontally: Bool = false
    @Published var currentTweet: Tweet? = nil

    var currentMedia: TweetMedia? {
        guard currentIndex >= 0, currentIndex < mediaList.count else { return nil }
        return mediaList[currentIndex]
    }

    var currentSourceRect: CGRect {
        Self.visiblePart(sourceRectForCurrentMedia())
    }

    private func sourceRectForCurrentMedia() -> CGRect {
        if let media = currentMedia {
            if let r = MediaFrameRegistry.shared.frame(for: media.mediaUrl), r != .zero {
                return r
            }
            if let r = MediaFrameRegistry.shared.frame(for: media.id), r != .zero {
                return r
            }
        }
        if currentIndex == initialIndex && sourceRect != .zero {
            return sourceRect
        }
        if sourceRect != .zero && currentIndex >= 0 && currentIndex < mediaList.count {
            let diff = CGFloat(currentIndex - initialIndex)
            let spacing: CGFloat = (mediaList.count == 2) ? 8.0 : 10.0
            let cardW = sourceRect.width
            let estimatedX = sourceRect.origin.x + diff * (cardW + spacing)
            return CGRect(x: estimatedX, y: sourceRect.origin.y, width: cardW, height: sourceRect.height)
        }
        return .zero
    }

    // A full-bleed card can be partly past the window's edge; the zoom starts from the part that is on screen.
    private static func visiblePart(_ rect: CGRect) -> CGRect {
        guard rect != .zero, let bounds = AppWindowOrigin.bounds else { return rect }
        let visible = rect.intersection(bounds)
        return visible.isNull || visible.isEmpty ? rect : visible
    }

    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var accumulatedScrollX: CGFloat = 0
    private var lastScrollTime = Date()
    // A two-finger swipe on the trackpad works as dragging the image: up or down follows the fingers and closes it,
    // sideways turns the page. The first movement of the gesture decides which.
    private enum SwipeAxis { case undecided, vertical, horizontal }
    private var swipeAxis: SwipeAxis = .undecided
    private var swipeVelocity: CGFloat = 0
    private var lastSwipeTimestamp: TimeInterval = 0

    /// How far, or how fast, the image has to travel for a drag or swipe to close the preview
    static let dismissDistance: CGFloat = 65
    static let dismissVelocity: CGFloat = 400

    /// Lets go of a vertical drag or swipe: past the distance or speed it closes the preview, short of it the image
    /// springs back
    func endVerticalDrag(translation: CGFloat, velocity: CGFloat) {
        if abs(translation) > Self.dismissDistance || abs(velocity) > Self.dismissVelocity {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                dragOffset = .zero
            }
        }
        isDraggingVertically = false
    }

    func present(mediaList: [TweetMedia], initialIndex: Int, sourceRect: CGRect = .zero, tweet: Tweet? = nil) {
        guard !PeekCoordinator.shared.suppressesActivation else { return }
        guard !mediaList.isEmpty, initialIndex >= 0, initialIndex < mediaList.count else { return }
        self.mediaList = mediaList
        self.initialIndex = initialIndex
        self.currentIndex = initialIndex
        self.sourceRect = sourceRect
        self.currentTweet = tweet
        self.isAnimatingOut = false
        self.isZoomExpanded = false

        // Register initial frame and pre-seed adjacent items if not already registered
        if sourceRect != .zero {
            MediaFrameRegistry.shared.register(key: mediaList[initialIndex].mediaUrl, frame: sourceRect)
            MediaFrameRegistry.shared.register(key: mediaList[initialIndex].id, frame: sourceRect)

            let spacing: CGFloat = (mediaList.count == 2) ? 8.0 : 10.0
            let cardW = sourceRect.width
            for (i, m) in mediaList.enumerated() {
                if MediaFrameRegistry.shared.frame(for: m.mediaUrl) == nil {
                    let offset = CGFloat(i - initialIndex) * (cardW + spacing)
                    let frame = CGRect(x: sourceRect.origin.x + offset, y: sourceRect.origin.y, width: cardW, height: sourceRect.height)
                    MediaFrameRegistry.shared.register(key: m.mediaUrl, frame: frame)
                    MediaFrameRegistry.shared.register(key: m.id, frame: frame)
                }
            }
        }

        // Ensure all gesture and transform states are cleanly reset to default
        resetTransforms()
        setupEventMonitors()

        self.isPresented = true
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                self.isZoomExpanded = true
            }
        }
    }

    func resetTransforms() {
        self.zoomScale = 1.0
        self.panOffset = .zero
        self.dragOffset = .zero
        self.isDraggingVertically = false
        self.isDraggingHorizontally = false
        self.accumulatedScrollX = 0
        self.swipeAxis = .undecided
    }

    func dismiss() {
        guard isPresented && !isAnimatingOut else { return }
        self.isAnimatingOut = true
        removeEventMonitors()
        // The overlay is removed only once the spring has fully settled on the thumbnail. A fixed delay shorter
        // than the spring cut it off a few points short, and the image visibly jumped the rest of the way.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85), completionCriteria: .removed) {
            self.isZoomExpanded = false
            self.dragOffset = .zero
            self.zoomScale = 1.0
            self.panOffset = .zero
        } completion: {
            self.finishDismiss()
        }
        // Safety net in case the completion never fires
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.finishDismiss()
        }
    }

    private func finishDismiss() {
        guard isPresented, isAnimatingOut else { return }
        self.isPresented = false
        self.sourceRect = .zero
        self.isAnimatingOut = false
        self.mediaList = []
        self.currentTweet = nil
        self.currentIndex = 0
        self.initialIndex = 0
        self.resetTransforms()
        // The positions were only for this presentation; keeping one per picture viewed grows with the session.
        MediaFrameRegistry.shared.clear()
    }

    func next() {
        select(index: currentIndex + 1)
    }

    func prev() {
        select(index: currentIndex - 1)
    }

    func select(index: Int, animated: Bool = true) {
        guard index >= 0, index < mediaList.count, index != currentIndex else { return }
        let apply = {
            self.resetTransforms()
            self.currentIndex = index
        }
        if animated {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                apply()
            }
        } else {
            apply()
        }
    }

    func toggleZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            if self.zoomScale > 1.05 {
                self.zoomScale = 1.0
                self.panOffset = .zero
            } else {
                self.zoomScale = 2.5
            }
        }
    }

    private func setupEventMonitors() {
        removeEventMonitors()

        // 1. Keyboard Arrow Keys (Left / Right / Esc)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isPresented else { return event }
            switch event.keyCode {
            case 123: // Left Arrow (←)
                if self.zoomScale > 1.05 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.zoomScale = 1.0
                        self.panOffset = .zero
                    }
                }
                self.prev()
                return nil
            case 124: // Right Arrow (→)
                if self.zoomScale > 1.05 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.zoomScale = 1.0
                        self.panOffset = .zero
                    }
                }
                self.next()
                return nil
            case 53: // Esc
                if self.zoomScale > 1.05 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.zoomScale = 1.0
                        self.panOffset = .zero
                    }
                } else {
                    self.dismiss()
                }
                return nil
            default:
                return event
            }
        }

        // 2. Trackpad Two-Finger Pinch (Magnify)
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self = self, self.isPresented else { return event }
            let delta = event.magnification
            let newScale = max(1.0, min(5.0, self.zoomScale + delta * 2.2))
            self.zoomScale = newScale
            if newScale <= 1.0 {
                self.panOffset = .zero
            }
            return nil
        }

        // 3. Trackpad Two-Finger Swipe / Pan (scrollWheel)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.isPresented else { return event }

            // If currently zoomed in, two-finger scroll smoothly pans the image within exact image boundaries
            if self.zoomScale > 1.05 {
                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY
                let limitX = max(40, self.maxPanLimit.width)
                let limitY = max(40, self.maxPanLimit.height)
                self.panOffset.width = min(limitX, max(-limitX, self.panOffset.width + dx))
                self.panOffset.height = min(limitY, max(-limitY, self.panOffset.height + dy))
                return nil // Prevent background scroll
            }

            // The momentum after the fingers lift belongs to the gesture that has already been handled
            if event.momentumPhase != [] { return nil }

            // A trackpad gesture (one with phases); a mouse wheel has none and only turns pages, as before
            if event.phase != [] {
                if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                    self.swipeAxis = .undecided
                    self.swipeVelocity = 0
                    self.lastSwipeTimestamp = event.timestamp
                }
                // Where the fingers went, whichever way scrolling is set to run
                let fingerY = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
                if self.swipeAxis == .undecided {
                    let dx = abs(event.scrollingDeltaX), dy = abs(fingerY)
                    if dy > 1.5 && dy > dx * 1.2 {
                        self.swipeAxis = .vertical
                        self.isDraggingVertically = true
                    } else if dx > 1.5 && dx > dy {
                        self.swipeAxis = .horizontal
                    }
                }
                if self.swipeAxis == .vertical {
                    self.dragOffset = CGSize(width: 0, height: self.dragOffset.height + fingerY)
                    // Time since the fingers last moved
                    let gap = event.timestamp - self.lastSwipeTimestamp
                    if fingerY != 0 {
                        self.swipeVelocity = fingerY / CGFloat(max(gap, 0.004))
                        self.lastSwipeTimestamp = event.timestamp
                    }
                    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                        self.swipeAxis = .undecided
                        // Holding still before lifting the fingers leaves no speed behind
                        let paused = fingerY == 0 && gap > 0.08
                        self.endVerticalDrag(translation: self.dragOffset.height, velocity: paused ? 0 : self.swipeVelocity)
                    }
                    return nil
                }
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                    self.swipeAxis = .undecided
                }
            }

            // In standard zoom, handle horizontal swipe between images
            if self.mediaList.count > 1 {
                let deltaX = event.scrollingDeltaX
                if abs(deltaX) > 0.4 {
                    self.accumulatedScrollX += deltaX

                    let threshold: CGFloat = 24.0
                    let now = Date()
                    if now.timeIntervalSince(self.lastScrollTime) > 0.28 {
                        if self.accumulatedScrollX > threshold {
                            self.lastScrollTime = now
                            self.accumulatedScrollX = 0
                            self.prev()
                            return nil
                        } else if self.accumulatedScrollX < -threshold {
                            self.lastScrollTime = now
                            self.accumulatedScrollX = 0
                            self.next()
                            return nil
                        }
                    }
                }

                if event.phase == .ended || event.phase == .cancelled {
                    self.accumulatedScrollX = 0
                }
            }

            // Always absorb scroll events while lightbox is active to protect background timeline
            return nil
        }
    }

    private func removeEventMonitors() {
        if let km = keyMonitor {
            NSEvent.removeMonitor(km)
            keyMonitor = nil
        }
        if let sm = scrollMonitor {
            NSEvent.removeMonitor(sm)
            scrollMonitor = nil
        }
        if let mm = magnifyMonitor {
            NSEvent.removeMonitor(mm)
            magnifyMonitor = nil
        }
        accumulatedScrollX = 0
    }

    deinit {
        removeEventMonitors()
    }
}
