//
//  ImageLightboxView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit

// MARK: - Lightbox State Manager
final class LightboxManager: ObservableObject {
    static let shared = LightboxManager()
    
    @Published var isPresented: Bool = false
    @Published var mediaList: [TweetMedia] = []
    @Published var currentIndex: Int = 0
    @Published var isAnimatingOut: Bool = false
    @Published var sourceRect: CGRect = .zero
    @Published var isZoomExpanded: Bool = false
    
    // Zoom & Pan State
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero
    
    // Dismiss / Swipe Drag State
    @Published var dragOffset: CGSize = .zero
    @Published var isDraggingVertically: Bool = false
    @Published var isDraggingHorizontally: Bool = false
    
    var currentMedia: TweetMedia? {
        guard currentIndex >= 0, currentIndex < mediaList.count else { return nil }
        return mediaList[currentIndex]
    }
    
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var accumulatedScrollX: CGFloat = 0
    private var lastScrollTime = Date()
    
    func present(mediaList: [TweetMedia], initialIndex: Int, sourceRect: CGRect = .zero) {
        guard !mediaList.isEmpty, initialIndex >= 0, initialIndex < mediaList.count else { return }
        self.mediaList = mediaList
        self.currentIndex = initialIndex
        self.sourceRect = sourceRect
        self.isAnimatingOut = false
        self.isZoomExpanded = false
        
        // Ensure all gesture and transform states are cleanly reset to default
        resetTransforms()
        setupEventMonitors()
        
        self.isPresented = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.isZoomExpanded = true
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
            
            // If currently zoomed in, two-finger scroll smoothly pans the image
            if self.zoomScale > 1.05 {
                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY
                self.panOffset.width += dx
                self.panOffset.height += dy
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
                let windowSize = windowGeo.size
                // 3/4 box dimensions requested by user
                let boxWidth = windowSize.width * 0.75
                let boxHeight = windowSize.height * 0.75
                let windowCenter = CGPoint(x: windowSize.width / 2.0, y: windowSize.height / 2.0)
                
                // Pure rect-tracking zoom: calculate offset and scale from sourceRect
                let hasSourceRect = manager.sourceRect != .zero
                let sourceScale: CGFloat = hasSourceRect ? max(0.08, min(manager.sourceRect.width / boxWidth, manager.sourceRect.height / boxHeight)) : 0.85
                let sourceOffsetX: CGFloat = hasSourceRect ? (manager.sourceRect.midX - windowCenter.x) : 0
                let sourceOffsetY: CGFloat = hasSourceRect ? (manager.sourceRect.midY - windowCenter.y) : 0
                
                let animScale: CGFloat = manager.isZoomExpanded ? 1.0 : sourceScale
                let animOffsetX: CGFloat = manager.isZoomExpanded ? 0 : sourceOffsetX
                let animOffsetY: CGFloat = manager.isZoomExpanded ? 0 : sourceOffsetY
                
                let effectiveScale = manager.zoomScale * pinchScale * animScale
                
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
                    
                    // 2. The 3/4 Bounding Box: matching longest edge of current image
                    ZStack {
                        if let currentMedia = manager.currentMedia {
                            CachedAsyncImage(
                                urlString: originalUrl(currentMedia.mediaUrl),
                                placeholderColor: Color(white: 0.08),
                                contentMode: .fit
                            )
                            .frame(maxWidth: boxWidth, maxHeight: boxHeight)
                            .clipShape(RoundedRectangle(cornerRadius: manager.isZoomExpanded ? 8 : 16, style: .continuous))
                            .shadow(color: Color.black.opacity(manager.isZoomExpanded ? 0.50 : 0.0), radius: 24, x: 0, y: 8)
                            .scaleEffect(effectiveScale * verticalScale)
                            .offset(
                                x: (manager.zoomScale > 1.05 ? manager.panOffset.width : manager.dragOffset.width) + animOffsetX,
                                y: (manager.zoomScale > 1.05 ? manager.panOffset.height : manager.dragOffset.height) + animOffsetY
                            )
                            .animation(.spring(response: 0.30, dampingFraction: 0.86), value: manager.currentIndex)
                            .id(manager.currentIndex)
                            .onTapGesture(count: 2) {
                                manager.toggleZoom()
                            }
                        }
                    }
                    .frame(width: boxWidth, height: boxHeight)
                    
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
                                    .padding(.leading, max(12, (windowSize.width - boxWidth) / 2 - 46))
                            }
                            Spacer()
                            if manager.currentIndex < manager.mediaList.count - 1 {
                                chevronButton(icon: "chevron.right") { manager.next() }
                                    .padding(.trailing, max(12, (windowSize.width - boxWidth) / 2 - 46))
                            }
                        }
                        .opacity(manager.isZoomExpanded ? headerOpacity : 0.0)
                    }
                }
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
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            handleDragChanged(value, boxWidth: boxWidth, boxHeight: boxHeight)
                        }
                        .onEnded { value in
                            handleDragEnded(value)
                        }
                )
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
    private func handleDragChanged(_ value: DragGesture.Value, boxWidth: CGFloat, boxHeight: CGFloat) {
        if manager.zoomScale > 1.05 {
            let maxPanX = max(0, (boxWidth * (manager.zoomScale - 1)) / 1.5)
            let maxPanY = max(0, (boxHeight * (manager.zoomScale - 1)) / 1.5)
            
            manager.panOffset.width = min(maxPanX, max(-maxPanX, manager.panOffset.width + value.translation.width * 0.15))
            manager.panOffset.height = min(maxPanY, max(-maxPanY, manager.panOffset.height + value.translation.height * 0.15))
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
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        if manager.zoomScale > 1.05 {
            return
        }
        
        if manager.isDraggingVertically {
            if abs(value.translation.height) > 65 || abs(value.velocity.height) > 400 {
                // Must explicitly reset dragOffset so subsequent opens are clean
                manager.dragOffset = .zero
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
