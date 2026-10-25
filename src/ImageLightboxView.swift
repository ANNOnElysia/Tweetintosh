//
//  ImageLightboxView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit

// MARK: - Media Frame Registry (Tracks thumbnail coordinates in AppWindow space)
final class MediaFrameRegistry {
    static let shared = MediaFrameRegistry()
    private var frames: [String: CGRect] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    func register(key: String, frame: CGRect) {
        guard frame.width > 5, frame.height > 5 else { return }
        lock.lock()
        frames[key] = frame
        lock.unlock()
    }
    
    func frame(for key: String) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return frames[key]
    }
    
    func clear() {
        lock.lock()
        frames.removeAll()
        lock.unlock()
    }
}

// MARK: - Preference Key for Tracking Media View Geometry
struct MediaFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
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
    var isPanningZoom: Bool = false
    
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
    
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var accumulatedScrollX: CGFloat = 0
    private var lastScrollTime = Date()
    
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
    }
    
    func dismiss() {
        guard isPresented && !isAnimatingOut else { return }
        self.isAnimatingOut = true
        removeEventMonitors()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            self.isZoomExpanded = false
            self.dragOffset = .zero
            self.zoomScale = 1.0
            self.panOffset = .zero
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            self.isPresented = false
            self.sourceRect = .zero
            self.isAnimatingOut = false
            self.mediaList = []
            self.currentIndex = 0
            self.initialIndex = 0
            self.resetTransforms()
        }
    }
    
    func next() {
        guard currentIndex < mediaList.count - 1 else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            self.resetTransforms()
            self.currentIndex += 1
        }
    }
    
    func prev() {
        guard currentIndex > 0 else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            self.resetTransforms()
            self.currentIndex -= 1
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

// MARK: - Lightbox Overlay View
struct ImageLightboxOverlay: View {
    @ObservedObject var manager = LightboxManager.shared
    @GestureState private var pinchScale: CGFloat = 1.0
    
    var body: some View {
        if manager.isPresented {
            GeometryReader { windowGeo in
                let windowFrame = windowGeo.frame(in: .named("AppWindow"))
                let windowSize = windowFrame.size
                
                let currentMedia = manager.currentMedia
                let mediaRatio: CGFloat = {
                    if let m = currentMedia, m.aspectRatio > 0 {
                        return m.aspectRatio
                    }
                    return 1.0
                }()
                
                // 3/4 box dimensions requested by user
                let maxBoxW = windowSize.width * 0.75
                let maxBoxH = windowSize.height * 0.75
                
                let expandedSize: CGSize = {
                    if maxBoxW / maxBoxH > mediaRatio {
                        let h = maxBoxH
                        let w = h * mediaRatio
                        return CGSize(width: w, height: h)
                    } else {
                        let w = maxBoxW
                        let h = w / mediaRatio
                        return CGSize(width: w, height: h)
                    }
                }()
                
                let currentSourceRect = manager.currentSourceRect
                let hasSourceRect = currentSourceRect != .zero
                
                // Exact target width & height: matches thumbnail precisely when collapsed!
                let targetWidth: CGFloat = manager.isZoomExpanded ? expandedSize.width : (hasSourceRect ? currentSourceRect.width : expandedSize.width * 0.8)
                let targetHeight: CGFloat = manager.isZoomExpanded ? expandedSize.height : (hasSourceRect ? currentSourceRect.height : expandedSize.height * 0.8)
                
                // Exact target offset: calculates distance from windowFrame center to sourceRect center in "AppWindow" coordinate space
                // Using windowFrame.midX and windowFrame.midY completely accounts for window safe area insets (e.g. titlebar height)
                let targetOffsetX: CGFloat = manager.isZoomExpanded ? 0 : (hasSourceRect ? (currentSourceRect.midX - windowFrame.midX) : 0)
                let targetOffsetY: CGFloat = manager.isZoomExpanded ? 0 : (hasSourceRect ? (currentSourceRect.midY - windowFrame.midY) : 0)
                
                let targetCornerRadius: CGFloat = manager.isZoomExpanded ? 8 : 16
                let targetBorderOpacity: Double = manager.isZoomExpanded ? 0.0 : 1.0
                
                let effectiveScale = manager.zoomScale * pinchScale
                
                let maxPanX: CGFloat = {
                    guard effectiveScale > 1.0 else { return 0 }
                    let scaledW = expandedSize.width * effectiveScale
                    let edgeLimit = max(0, (scaledW - windowSize.width) / 2 + 40)
                    let centerLimit = (expandedSize.width * (effectiveScale - 1)) / 2
                    return max(edgeLimit, centerLimit)
                }()
                
                let maxPanY: CGFloat = {
                    guard effectiveScale > 1.0 else { return 0 }
                    let scaledH = expandedSize.height * effectiveScale
                    let edgeLimit = max(0, (scaledH - windowSize.height) / 2 + 40)
                    let centerLimit = (expandedSize.height * (effectiveScale - 1)) / 2
                    return max(edgeLimit, centerLimit)
                }()
                
                ZStack {
                    // 1. Dark Backdrop with interactive opacity
                    Color.black
                        .opacity((manager.isZoomExpanded ? backdropOpacity : 0.0) * (manager.isAnimatingOut ? 0.0 : 1.0))
                        .ignoresSafeArea()
                        .onTapGesture {
                            if manager.zoomScale > 1.05 {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                    manager.zoomScale = 1.0
                                    manager.panOffset = .zero
                                }
                            } else {
                                manager.dismiss()
                            }
                        }
                    
                    // 2. The Zooming Image Container (exact frame & corner radius matching timeline card)
                    if let currentMedia = currentMedia {
                        CachedAsyncImage(
                            urlString: MediaHelpers.originalImageUrl(currentMedia.mediaUrl),
                            placeholderColor: Color(white: 0.08),
                            contentMode: .fill
                        )
                        .frame(width: max(1, targetWidth), height: max(1, targetHeight))
                        .clipShape(RoundedRectangle(cornerRadius: targetCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: targetCornerRadius, style: .continuous)
                                .stroke(ThemeManager.border.opacity(targetBorderOpacity), lineWidth: 0.6)
                        )
                        .shadow(color: Color.black.opacity(manager.isZoomExpanded ? 0.50 : 0.0), radius: 24, x: 0, y: 8)
                        .scaleEffect(effectiveScale * verticalScale)
                        .offset(
                            x: (manager.zoomScale > 1.05 ? manager.panOffset.width : manager.dragOffset.width) + targetOffsetX,
                            y: (manager.zoomScale > 1.05 ? manager.panOffset.height : manager.dragOffset.height) + targetOffsetY
                        )
                        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: manager.currentIndex)
                        .id(manager.currentIndex)
                        .onTapGesture(count: 2) {
                            manager.toggleZoom()
                        }
                        .mediaContextMenu(media: currentMedia, tweet: manager.currentTweet)
                    }
                    
                    // 3. Top Header Bar (Pagination Capsule / Zoom % + Close Button)
                    VStack {
                        HStack(alignment: .center) {
                            headerIndicator
                                .padding(.leading, 24)
                            
                            Spacer()
                            
                            Button(action: { manager.dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(white: 0.80))
                                    .padding(20)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .opacity(manager.isZoomExpanded ? headerOpacity : 0.0)
                        
                        Spacer()
                    }
                    
                    // 4. Subtle Navigation Chevrons for multi-image (hidden when zoomed in)
                    if manager.mediaList.count > 1 && manager.zoomScale <= 1.05 {
                        HStack {
                            if manager.currentIndex > 0 {
                                chevronButton(icon: "chevron.left") { manager.prev() }
                                    .padding(.leading, max(12, (windowSize.width - maxBoxW) / 2 - 46))
                            }
                            Spacer()
                            if manager.currentIndex < manager.mediaList.count - 1 {
                                chevronButton(icon: "chevron.right") { manager.next() }
                                    .padding(.trailing, max(12, (windowSize.width - maxBoxW) / 2 - 46))
                            }
                        }
                        .opacity(manager.isZoomExpanded ? headerOpacity : 0.0)
                    }
                }
                .frame(width: windowSize.width, height: windowSize.height)
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($pinchScale) { val, state, _ in
                            state = val
                        }
                        .onEnded { val in
                            let target = max(1.0, min(5.0, manager.zoomScale * val))
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                manager.zoomScale = target
                                if target <= 1.0 {
                                    manager.panOffset = .zero
                                } else {
                                    let limitX = (expandedSize.width * (target - 1)) / 2
                                    let limitY = (expandedSize.height * (target - 1)) / 2
                                    manager.panOffset.width = min(limitX, max(-limitX, manager.panOffset.width))
                                    manager.panOffset.height = min(limitY, max(-limitY, manager.panOffset.height))
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            handleDragChanged(value, maxPanX: maxPanX, maxPanY: maxPanY)
                        }
                        .onEnded { value in
                            handleDragEnded(value, maxPanX: maxPanX, maxPanY: maxPanY)
                        }
                )
                .onChange(of: effectiveScale) {
                    manager.maxPanLimit = CGSize(width: maxPanX, height: maxPanY)
                }
                .onAppear {
                    manager.maxPanLimit = CGSize(width: maxPanX, height: maxPanY)
                }
            }
            .transition(.identity)
            .zIndex(999)
            .onAppear {
                manager.resetTransforms()
            }
        }
    }
    
    @ViewBuilder private var headerIndicator: some View {
        HStack(spacing: 8) {
            if manager.mediaList.count > 1 {
                Text("\(manager.currentIndex + 1) / \(manager.mediaList.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.90))
            }
            
            if manager.zoomScale > 1.05 {
                Text("\(Int(manager.zoomScale * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(white: 0.70))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.60)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
        .opacity((manager.mediaList.count > 1 || manager.zoomScale > 1.05) ? 1.0 : 0.0)
    }
    
    private func chevronButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.65)))
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Gesture Mechanics
    private func handleDragChanged(_ value: DragGesture.Value, maxPanX: CGFloat, maxPanY: CGFloat) {
        if manager.zoomScale > 1.05 {
            if !manager.isPanningZoom {
                manager.isPanningZoom = true
                manager.startPanOffset = manager.panOffset
            }
            let targetX = manager.startPanOffset.width + value.translation.width
            let targetY = manager.startPanOffset.height + value.translation.height
            
            // Apple HIG rubber-band resistance when dragging beyond pan boundaries
            let clampedX: CGFloat
            if targetX > maxPanX {
                clampedX = maxPanX + (targetX - maxPanX) * 0.35
            } else if targetX < -maxPanX {
                clampedX = -maxPanX + (targetX + maxPanX) * 0.35
            } else {
                clampedX = targetX
            }
            
            let clampedY: CGFloat
            if targetY > maxPanY {
                clampedY = maxPanY + (targetY - maxPanY) * 0.35
            } else if targetY < -maxPanY {
                clampedY = -maxPanY + (targetY + maxPanY) * 0.35
            } else {
                clampedY = targetY
            }
            
            manager.panOffset = CGSize(width: clampedX, height: clampedY)
            return
        }
        
        let trans = value.translation
        if !manager.isDraggingVertically && !manager.isDraggingHorizontally {
            if abs(trans.height) > abs(trans.width) * 1.2 {
                manager.isDraggingVertically = true
            } else if abs(trans.width) > abs(trans.height) {
                manager.isDraggingHorizontally = true
            }
        }
        
        if manager.isDraggingVertically {
            manager.dragOffset = CGSize(width: 0, height: trans.height)
        } else if manager.isDraggingHorizontally {
            var dx = trans.width
            if (manager.currentIndex == 0 && dx > 0) || (manager.currentIndex == manager.mediaList.count - 1 && dx < 0) {
                dx = dx * 0.35 // Rubber band resistance
            }
            manager.dragOffset = CGSize(width: dx, height: 0)
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, maxPanX: CGFloat, maxPanY: CGFloat) {
        if manager.zoomScale > 1.05 {
            manager.isPanningZoom = false
            let finalX = min(maxPanX, max(-maxPanX, manager.panOffset.width))
            let finalY = min(maxPanY, max(-maxPanY, manager.panOffset.height))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                manager.panOffset = CGSize(width: finalX, height: finalY)
            }
            return
        }
        
        if manager.isDraggingVertically {
            if abs(value.translation.height) > 65 || abs(value.velocity.height) > 400 {
                manager.dismiss()
            } else {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                    manager.dragOffset = .zero
                }
            }
        } else if manager.isDraggingHorizontally {
            let dx = value.translation.width
            let vx = value.velocity.width
            
            if (dx < -40 || vx < -250) && manager.currentIndex < manager.mediaList.count - 1 {
                manager.next()
            } else if (dx > 40 || vx > 250) && manager.currentIndex > 0 {
                manager.prev()
            }
            
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                manager.dragOffset = .zero
            }
        } else {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                manager.dragOffset = .zero
            }
        }
        
        manager.isDraggingVertically = false
        manager.isDraggingHorizontally = false
    }
    
    private var backdropOpacity: Double {
        let dragDist = abs(manager.dragOffset.height)
        return max(0.40, min(0.94, 0.94 - Double(dragDist) / 500.0))
    }
    
    private var headerOpacity: Double {
        let dragDist = abs(manager.dragOffset.height)
        return max(0.50, 1.0 - Double(dragDist) / 250.0)
    }
    
    private var verticalScale: CGFloat {
        if manager.isAnimatingOut || !manager.isZoomExpanded { return 1.0 }
        let dragDist = abs(manager.dragOffset.height)
        return max(0.72, 1.0 - dragDist / 1000.0)
    }
    
    private func originalUrl(_ url: String) -> String {
        if url.contains("pbs.twimg.com/media") {
            let base = url.components(separatedBy: "?").first ?? url
            return "\(base)?format=jpg&name=orig"
        }
        return url
    }
}
