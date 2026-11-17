//
//  ImageLightboxView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

// MARK: - Lightbox Overlay View
struct ImageLightboxOverlay: View {
    @ObservedObject var manager = LightboxManager.shared
    @ObservedObject private var theme = ThemeManager.shared
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
                            .buttonStyle(.target)
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

                    // 5. Bottom Thumbnail Scrubber (matches X's centered, expandable active thumbnail bar)
                    if manager.mediaList.count > 1 && manager.zoomScale <= 1.05 {
                        VStack {
                            Spacer()
                            LightboxThumbnailScrubber(
                                mediaList: manager.mediaList,
                                currentIndex: manager.currentIndex,
                                onSelect: { idx, animated in
                                    manager.select(index: idx, animated: animated)
                                }
                            )
                            .padding(.bottom, 22)
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
        .buttonStyle(.target)
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
            manager.endVerticalDrag(translation: value.translation.height, velocity: value.velocity.height)
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

// MARK: - Bottom Thumbnail Scrubber
/// Centered horizontal thumbnail strip matching X's photo viewer: the active thumbnail expands with a crisp white
/// border and extra breathing room, and dragging the strip scrubs through photos in real time.
private struct LightboxThumbnailScrubber: View {
    let mediaList: [TweetMedia]
    let currentIndex: Int
    let onSelect: (Int, Bool) -> Void

    @State private var scrubStartIndex: Int?
    @State private var scrubDragX: CGFloat = 0

    private let inactiveSize: CGFloat = 32
    private let activeSize: CGFloat = 38
    private let spacing: CGFloat = 4
    private let activeSideGap: CGFloat = 5

    private var step: CGFloat { inactiveSize + spacing }

    /// Horizontal offset that places `currentIndex`'s center at `x = 0` (screen center).
    private var centerOffset: CGFloat {
        let count = mediaList.count
        let activeTotal = activeSize + activeSideGap * 2
        let totalWidth = CGFloat(max(0, count - 1)) * inactiveSize + activeTotal + CGFloat(max(0, count - 1)) * spacing
        let selectedCenter = CGFloat(currentIndex) * step + activeTotal / 2
        return (totalWidth / 2) - selectedCenter
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(mediaList.enumerated()), id: \.offset) { index, media in
                let isSelected = index == currentIndex
                let size = isSelected ? activeSize : inactiveSize
                let corner: CGFloat = isSelected ? 7 : 5

                CachedAsyncImage(
                    urlString: thumbUrl(media.mediaUrl),
                    placeholderColor: Color(white: 0.14),
                    contentMode: .fill,
                    targetSize: CGSize(width: activeSize * 2, height: activeSize * 2)
                )
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.white, lineWidth: isSelected ? 1.75 : 0)
                )
                .opacity(isSelected ? 1.0 : 0.45)
                .padding(.horizontal, isSelected ? activeSideGap : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(index, true)
                }
            }
        }
        .frame(height: activeSize + 4)
        .offset(x: centerOffset + scrubDragX)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: currentIndex)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if scrubStartIndex == nil {
                        scrubStartIndex = currentIndex
                    }
                    let start = scrubStartIndex ?? currentIndex
                    let deltaSteps = Int((-value.translation.width / step).rounded())
                    let target = min(mediaList.count - 1, max(0, start + deltaSteps))
                    if target != currentIndex {
                        onSelect(target, true)
                    }
                    // Keep 1:1 finger tracking relative to the newly centered index, with rubber-band resistance at ends
                    let remainder = value.translation.width - CGFloat(start - target) * step
                    if (target == 0 && remainder > 0) || (target == mediaList.count - 1 && remainder < 0) {
                        scrubDragX = remainder * 0.35
                    } else {
                        scrubDragX = remainder
                    }
                }
                .onEnded { _ in
                    scrubStartIndex = nil
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        scrubDragX = 0
                    }
                }
        )
    }

    private func thumbUrl(_ original: String) -> String {
        if original.contains("pbs.twimg.com/media"), !original.contains("?") {
            return "\(original)?format=jpg&name=medium"
        }
        return original
    }
}
