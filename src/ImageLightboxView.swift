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
    
    func present(mediaList: [TweetMedia], initialIndex: Int, sourceRect: CGRect = .zero) {
        guard !mediaList.isEmpty, initialIndex >= 0, initialIndex < mediaList.count else { return }
        self.mediaList = mediaList
        self.currentIndex = initialIndex
        self.sourceRect = sourceRect
        self.isAnimatingOut = false
        
        withAnimation(.easeInOut(duration: 0.22)) {
            self.isPresented = true
        }
    }
    
    func dismiss() {
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
        if currentIndex < mediaList.count - 1 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                currentIndex += 1
            }
        }
    }
    
    func prev() {
        if currentIndex > 0 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                currentIndex -= 1
            }
        }
    }
}

// MARK: - Lightbox Drag State (Avoids @State macro in CommandLineTools)
final class LightboxDragState: ObservableObject {
    @Published var dragOffset: CGSize = .zero
    @Published var isDraggingVertically = false
    @Published var isDraggingHorizontally = false
}

// MARK: - Lightbox Overlay View (Restored to previous version with snap & rubber banding)
struct ImageLightboxOverlay: View {
    @ObservedObject var manager = LightboxManager.shared
    @StateObject private var dragState = LightboxDragState()
    
    var body: some View {
        if manager.isPresented {
            GeometryReader { windowGeo in
                let windowSize = windowGeo.size
                
                ZStack {
                    // 1. Dark Backdrop with interactive opacity
                    Color.black
                        .opacity(backdropOpacity)
                        .ignoresSafeArea()
                        .onTapGesture {
                            manager.dismiss()
                        }
                    
                    // 2. Multi-image Horizontal Track with Magnetic Snap
                    HStack(spacing: 24) {
                        ForEach(0..<manager.mediaList.count, id: \.self) { index in
                            let media = manager.mediaList[index]
                            
                            CachedAsyncImage(
                                urlString: originalUrl(media.mediaUrl),
                                placeholderColor: Color(white: 0.06),
                                contentMode: .fit
                            )
                            .frame(width: max(200, windowSize.width - 64), height: max(200, windowSize.height - 72))
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(width: windowSize.width, height: windowSize.height)
                    // Apply horizontal tracking & vertical gesture offset
                    .offset(x: -CGFloat(manager.currentIndex) * (windowSize.width - 64 + 24) + dragState.dragOffset.width)
                    .offset(y: dragState.dragOffset.height)
                    .scaleEffect(verticalScale)
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                handleDragChanged(value)
                            }
                            .onEnded { value in
                                handleDragEnded(value, windowWidth: windowSize.width - 64)
                            }
                    )
                    
                    // 3. Top Header Bar (Close button & Pagination indicator)
                    VStack {
                        HStack(alignment: .center) {
                            if manager.mediaList.count > 1 {
                                Text("\(manager.currentIndex + 1) / \(manager.mediaList.count)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(white: 0.85))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                                    .padding(.leading, 24)
                            }
                            
                            Spacer()
                            
                            Button(action: { manager.dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(white: 0.8))
                                    .padding(20)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .keyboardShortcut(.cancelAction) // Esc key
                        }
                        .opacity(1.0 - abs(dragState.dragOffset.height) / 100)
                        
                        Spacer()
                    }
                    
                    // 4. Subtle Navigation Chevrons for multi-image
                    if manager.mediaList.count > 1 {
                        HStack {
                            if manager.currentIndex > 0 {
                                chevronButton(icon: "chevron.left") { manager.prev() }
                                    .padding(.leading, 12)
                            }
                            Spacer()
                            if manager.currentIndex < manager.mediaList.count - 1 {
                                chevronButton(icon: "chevron.right") { manager.next() }
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                }
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
        
        // Determine primary direction if not decided
        if !dragState.isDraggingVertically && !dragState.isDraggingHorizontally {
            if abs(trans.height) > abs(trans.width) * 1.2 {
                dragState.isDraggingVertically = true
            } else if abs(trans.width) > abs(trans.height) {
                dragState.isDraggingHorizontally = true
            }
        }
        
        if dragState.isDraggingVertically {
            // Track vertical movement for return-to-origin dismiss
            dragState.dragOffset = CGSize(width: 0, height: trans.height)
        } else if dragState.isDraggingHorizontally {
            // Track horizontal movement for fluid swiping
            // Add rubber banding at edges
            var dx = trans.width
            if (manager.currentIndex == 0 && dx > 0) || (manager.currentIndex == manager.mediaList.count - 1 && dx < 0) {
                dx = dx * 0.35 // Rubber band resistance
            }
            dragState.dragOffset = CGSize(width: dx, height: 0)
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, windowWidth: CGFloat) {
        if dragState.isDraggingVertically {
            // Vertical dismiss threshold: 65px or downward velocity
            if abs(value.translation.height) > 65 || abs(value.velocity.height) > 400 {
                manager.dismiss()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragState.dragOffset = .zero
                }
            }
        } else if dragState.isDraggingHorizontally {
            // Horizontal magnetic snap threshold: 65px or swipe velocity
            let dx = value.translation.width
            let vx = value.velocity.width
            
            if (dx < -65 || vx < -300) && manager.currentIndex < manager.mediaList.count - 1 {
                // Snap to next image
                manager.next()
            } else if (dx > 65 || vx > 300) && manager.currentIndex > 0 {
                // Snap to previous image
                manager.prev()
            }
            
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
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
