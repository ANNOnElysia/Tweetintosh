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
    @Published var sourceRect: CGRect = .zero
    @Published var isAnimatingOut: Bool = false
    
    var currentMedia: TweetMedia? {
        guard currentIndex >= 0, currentIndex < mediaList.count else { return nil }
        return mediaList[currentIndex]
    }
    
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var accumulatedScrollX: CGFloat = 0
    private var lastScrollTime = Date()
    
    func present(mediaList: [TweetMedia], initialIndex: Int, sourceRect: CGRect = .zero) {
        guard !mediaList.isEmpty, initialIndex >= 0, initialIndex < mediaList.count else { return }
        self.mediaList = mediaList
        self.currentIndex = initialIndex
        self.sourceRect = sourceRect
        self.isAnimatingOut = false
        
        setupEventMonitors()
        
        withAnimation(.easeInOut(duration: 0.22)) {
            self.isPresented = true
        }
    }
    
    func dismiss() {
        removeEventMonitors()
        withAnimation(.easeInOut(duration: 0.20)) {
            self.isPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            self.isAnimatingOut = false
            self.mediaList = []
            self.currentIndex = 0
        }
    }
    
    func next() {
        guard currentIndex < mediaList.count - 1 else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            currentIndex += 1
        }
    }
    
    func prev() {
        guard currentIndex > 0 else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            currentIndex -= 1
        }
    }
    
    private func setupEventMonitors() {
        removeEventMonitors()
        
        // 1. Keyboard Arrow Keys (Left / Right / Esc)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isPresented else { return event }
            switch event.keyCode {
            case 123: // Left Arrow (←)
                self.prev()
                return nil
            case 124: // Right Arrow (→)
                self.next()
                return nil
            case 53: // Esc
                self.dismiss()
                return nil
            default:
                return event
            }
        }
        
        // 2. Trackpad Two-Finger Swipe (scrollWheel)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.isPresented, self.mediaList.count > 1 else { return event }
            
            let deltaX = event.scrollingDeltaX
            if abs(deltaX) > 0.4 {
                self.accumulatedScrollX += deltaX
                
                let threshold: CGFloat = 24.0
                let now = Date()
                if now.timeIntervalSince(self.lastScrollTime) > 0.28 {
                    if self.accumulatedScrollX > threshold {
                        // Swiped right -> Previous image
                        self.lastScrollTime = now
                        self.accumulatedScrollX = 0
                        self.prev()
                        return nil
                    } else if self.accumulatedScrollX < -threshold {
                        // Swiped left -> Next image
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
            
            return event
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
        accumulatedScrollX = 0
    }
    
    deinit {
        removeEventMonitors()
    }
}

// MARK: - Lightbox Drag State (Avoids @State macro in CommandLineTools)
final class LightboxDragState: ObservableObject {
    @Published var dragOffset: CGSize = .zero
    @Published var isDraggingVertically = false
    @Published var isDraggingHorizontally = false
}

// MARK: - Lightbox Overlay View
struct ImageLightboxOverlay: View {
    @ObservedObject var manager = LightboxManager.shared
    @StateObject private var dragState = LightboxDragState()
    
    var body: some View {
        if manager.isPresented {
            GeometryReader { windowGeo in
                let windowSize = windowGeo.size
                // 3/4 box dimensions requested by user
                let boxWidth = windowSize.width * 0.75
                let boxHeight = windowSize.height * 0.75
                
                ZStack {
                    // 1. Dark Backdrop with interactive opacity
                    Color.black
                        .opacity(backdropOpacity)
                        .ignoresSafeArea()
                        .onTapGesture {
                            manager.dismiss()
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
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: Color.black.opacity(0.50), radius: 24, x: 0, y: 8)
                            .offset(x: dragState.dragOffset.width, y: dragState.dragOffset.height)
                            .scaleEffect(verticalScale)
                            .animation(.spring(response: 0.30, dampingFraction: 0.86), value: manager.currentIndex)
                            .id(manager.currentIndex)
                        }
                    }
                    .frame(width: boxWidth, height: boxHeight)
                    
                    // 3. Top Header Bar (Pagination Capsule + Close Button)
                    VStack {
                        HStack(alignment: .center) {
                            if manager.mediaList.count > 1 {
                                Text("\(manager.currentIndex + 1) / \(manager.mediaList.count)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(white: 0.90))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.60)))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
                                    .padding(.leading, 24)
                            }
                            
                            Spacer()
                            
                            Button(action: { manager.dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(white: 0.80))
                                    .padding(20)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .opacity(1.0 - abs(dragState.dragOffset.height) / 100)
                        
                        Spacer()
                    }
                    
                    // 4. Subtle Navigation Chevrons for multi-image
                    if manager.mediaList.count > 1 {
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
                        .opacity(1.0 - abs(dragState.dragOffset.height) / 80)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            handleDragChanged(value)
                        }
                        .onEnded { value in
                            handleDragEnded(value)
                        }
                )
            }
            .transition(.opacity)
            .zIndex(999)
        }
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
    private func handleDragChanged(_ value: DragGesture.Value) {
        let trans = value.translation
        
        if !dragState.isDraggingVertically && !dragState.isDraggingHorizontally {
            if abs(trans.height) > abs(trans.width) * 1.2 {
                dragState.isDraggingVertically = true
            } else if abs(trans.width) > abs(trans.height) {
                dragState.isDraggingHorizontally = true
            }
        }
        
        if dragState.isDraggingVertically {
            dragState.dragOffset = CGSize(width: 0, height: trans.height)
        } else if dragState.isDraggingHorizontally {
            var dx = trans.width
            if (manager.currentIndex == 0 && dx > 0) || (manager.currentIndex == manager.mediaList.count - 1 && dx < 0) {
                dx = dx * 0.35 // Rubber band resistance
            }
            dragState.dragOffset = CGSize(width: dx, height: 0)
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value) {
        if dragState.isDraggingVertically {
            if abs(value.translation.height) > 65 || abs(value.velocity.height) > 400 {
                manager.dismiss()
            } else {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                    dragState.dragOffset = .zero
                }
            }
        } else if dragState.isDraggingHorizontally {
            let dx = value.translation.width
            let vx = value.velocity.width
            
            if (dx < -40 || vx < -250) && manager.currentIndex < manager.mediaList.count - 1 {
                manager.next()
            } else if (dx > 40 || vx > 250) && manager.currentIndex > 0 {
                manager.prev()
            }
            
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                dragState.dragOffset = .zero
            }
        }
        
        dragState.isDraggingVertically = false
        dragState.isDraggingHorizontally = false
    }
    
    private var backdropOpacity: Double {
        let dragDist = abs(dragState.dragOffset.height)
        return max(0.0, min(0.94, 0.94 - Double(dragDist) / 360.0))
    }
    
    private var verticalScale: CGFloat {
        let dragDist = abs(dragState.dragOffset.height)
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
