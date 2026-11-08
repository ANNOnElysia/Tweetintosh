//
//  SVGRefreshIndicatorView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit
import QuartzCore

struct CurveSegment {
    let cp1: CGPoint
    let cp2: CGPoint
    let p3: CGPoint
}

final class SVGRefreshIndicatorNSView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let shapeLayer = CAShapeLayer()
    
    private var pullProgress: CGFloat = 0.0
    private var isRefreshing: Bool = false
    private var colorScheme: AppThemeColor = .blue
    private var isAnimatingLoop: Bool = false
    // A single colour instead of the theme gradient, for places the gradient would vanish into (an accent button)
    private var tint: NSColor?
    
    // Cached path geometry
    private var cachedWidth: CGFloat = 0
    private var cachedHeight: CGFloat = 0
    
    // Level 2 de Casteljau subdivision helper to add 4x SVG points/segments for buttery smooth rendering
    private static func subdivideCubic(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> (CurveSegment, CurveSegment) {
        let p01 = CGPoint(x: (p0.x + p1.x) * 0.5, y: (p0.y + p1.y) * 0.5)
        let p12 = CGPoint(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
        let p23 = CGPoint(x: (p2.x + p3.x) * 0.5, y: (p2.y + p3.y) * 0.5)
        
        let p012 = CGPoint(x: (p01.x + p12.x) * 0.5, y: (p01.y + p12.y) * 0.5)
        let p123 = CGPoint(x: (p12.x + p23.x) * 0.5, y: (p12.y + p23.y) * 0.5)
        
        let p0123 = CGPoint(x: (p012.x + p123.x) * 0.5, y: (p012.y + p123.y) * 0.5)
        
        let seg1 = CurveSegment(cp1: p01, cp2: p012, p3: p0123)
        let seg2 = CurveSegment(cp1: p123, cp2: p23, p3: p3)
        return (seg1, seg2)
    }
    
    // 164 high-density cubic curves of cursive "loading" (4x density of original 41 curves)
    private static let denseMiddleCurves: [CurveSegment] = {
        let d = "M -362.67 618.00 C -362.67 618.00, 512.00 623.00, 522.67 620.00 C 571.52 606.26, 630.67 583.00, 654.00 543.00 C 677.33 503.00, 708.00 377.00, 676.67 377.00 C 639.33 377.00, 630.67 600.22, 679.33 601.00 C 710.67 601.50, 719.33 538.51, 737.80 538.51 C 739.33 538.51, 738.67 538.00, 738.67 538.00 C 738.67 538.00, 729.83 542.30, 729.83 541.49 C 711.33 556.00, 713.65 601.00, 743.33 601.00 C 786.00 601.00, 778.00 532.00, 759.33 532.00 C 742.00 532.00, 749.33 580.50, 782.67 580.50 C 810.00 580.50, 816.67 532.00, 840.67 532.00 C 860.00 532.00, 862.67 540.50, 862.67 540.50 C 862.67 540.50, 861.25 532.12, 841.08 532.12 C 814.41 532.12, 807.11 574.11, 812.00 586.50 C 817.33 600.00, 832.80 607.61, 848.67 585.00 C 855.33 575.50, 854.67 560.00, 854.67 560.00 C 854.67 560.00, 855.43 576.75, 860.00 588.00 C 869.33 611.00, 891.33 595.00, 898.67 583.50 C 904.47 574.39, 923.00 532.25, 942.33 532.25 C 942.33 532.12, 944.50 532.62, 944.50 532.62 C 944.50 532.62, 941.08 532.31, 941.08 532.38 C 938.58 532.53, 909.83 543.50, 909.83 575.00 C 909.83 590.50, 918.33 598.28, 925.69 598.28 C 942.00 598.28, 950.78 574.59, 951.33 573.75 C 965.67 552.25, 1007.33 395.50, 974.67 395.50 C 944.67 395.50, 944.67 540.50, 961.33 573.00 C 964.88 579.91, 972.00 597.75, 983.33 597.75 C 997.00 597.75, 1022.83 576.25, 1022.83 522.25 C 1022.83 505.38, 1011.33 604.00, 1037.67 604.00 C 1068.33 604.00, 1088.33 526.75, 1099.33 526.75 C 1110.33 526.75, 1101.00 596.75, 1105.33 596.75 C 1109.67 596.75, 1135.00 535.00, 1153.67 535.00 C 1169.00 535.00, 1149.67 601.00, 1171.33 601.00 C 1214.33 601.00, 1199.67 533.25, 1243.67 533.25 C 1254.67 533.25, 1263.00 542.25, 1263.00 542.25 C 1263.00 542.25, 1253.00 533.25, 1243.67 533.25 C 1211.00 533.25, 1193.25 588.76, 1224.33 598.75 C 1229.00 600.25, 1253.67 593.25, 1253.67 557.25 C 1253.67 543.25, 1252.67 687.40, 1252.67 724.50 C 1252.67 752.50, 1227.02 791.94, 1213.33 755.00 C 1206.67 737.00, 1220.00 678.00, 1242.67 651.50 C 1260.10 631.12, 1298.47 563.06, 1302.33 553.94 C 1304.00 550.00, 2246.67 552.00, 2246.67 552.00"
        let tokens = d.replacingOccurrences(of: ",", with: " ").split(separator: " ")
        var segs: [CurveSegment] = []
        var i = 0
        while i < tokens.count {
            let cmd = tokens[i]
            if cmd == "M" {
                i += 3
            } else if cmd == "C" {
                let p1 = CGPoint(x: Double(tokens[i+1])!, y: Double(tokens[i+2])!)
                let p2 = CGPoint(x: Double(tokens[i+3])!, y: Double(tokens[i+4])!)
                let p3 = CGPoint(x: Double(tokens[i+5])!, y: Double(tokens[i+6])!)
                segs.append(CurveSegment(cp1: p1, cp2: p2, p3: p3))
                i += 7
            } else {
                i += 1
            }
        }
        
        var currentP = segs[0].p3
        var dense: [CurveSegment] = []
        let rawMiddle = Array(segs[1..<(segs.count - 1)])
        
        for seg in rawMiddle {
            let (s1, s2) = subdivideCubic(p0: currentP, p1: seg.cp1, p2: seg.cp2, p3: seg.p3)
            let (s1a, s1b) = subdivideCubic(p0: currentP, p1: s1.cp1, p2: s1.cp2, p3: s1.p3)
            let (s2a, s2b) = subdivideCubic(p0: s1.p3, p1: s2.cp1, p2: s2.cp2, p3: s2.p3)
            dense.append(contentsOf: [s1a, s1b, s2a, s2b])
            currentP = seg.p3
        }
        return dense
    }()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    // A view leaving the window loses its running animations, and a List does that to rows as it recycles them
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, isRefreshing else { return }
        stopLoopAnimation()
        startLoopAnimationIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Non-interactive, transparent pass-through
    }
    
    private func setupLayers() {
        wantsLayer = true
        
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0.0, 0.5, 1.0]
        updateGradientColors()
        
        shapeLayer.lineWidth = 2.4
        shapeLayer.strokeColor = NSColor.white.cgColor
        shapeLayer.fillColor = nil
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        shapeLayer.strokeStart = 0.0
        shapeLayer.strokeEnd = 0.0
        
        gradientLayer.mask = shapeLayer
        layer?.addSublayer(gradientLayer)
    }
    
    private func updateGradientColors() {
        if let tint = tint {
            gradientLayer.colors = [tint.cgColor, tint.cgColor, tint.cgColor]
        } else {
            gradientLayer.colors = colorScheme.gradientColors.map { $0.cgColor }
        }
    }
    
    func configure(progress: CGFloat, isRefreshing: Bool, color: AppThemeColor, tint: NSColor? = nil) {
        let colorChanged = (self.colorScheme != color) || self.tint != tint
        self.tint = tint
        let refreshStateChanged = (self.isRefreshing != isRefreshing)
        self.pullProgress = progress
        self.isRefreshing = isRefreshing
        self.colorScheme = color
        
        if colorChanged {
            updateGradientColors()
        }
        
        if isRefreshing {
            if refreshStateChanged || !isAnimatingLoop {
                startLoopAnimationIfNeeded()
            }
        } else {
            stopLoopAnimation()
            let targetEnd = min(1.0, max(0.0, progress))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.strokeStart = 0.0
            shapeLayer.strokeEnd = targetEnd
            CATransaction.commit()
        }
    }
    
    // MARK: - 120Hz Core Animation Continuous Recycling (Total Duration: 2.4s)
    // Pull completes at 40pt (strokeStart=0.0, strokeEnd=1.0).
    // On release: strokeStart smoothly recycles from 0.0 to 1.0 (erasing from left to right),
    // followed by strokeEnd drawing in again if refreshing takes longer than 2.4s.
    // At EVERY frame, the line is a single, uninterrupted, continuous curve (NEVER broken or segmented).
    private func startLoopAnimationIfNeeded() {
        guard !isAnimatingLoop else { return }
        isAnimatingLoop = true
        
        let cycleDuration: CFTimeInterval = 2.4
        
        // Phase 1 (0.00 -> 0.65, 1.56s): strokeEnd is 1.0, strokeStart recycles from 0.0 -> 1.0 (left to right)
        // Phase 2 (0.65 -> 1.00, 0.84s): strokeStart is 0.0, strokeEnd draws in from 0.0 -> 1.0 (left to right)
        let keyTimes: [NSNumber] = [0.00, 0.65, 0.6501, 1.00]
        let startValues: [NSNumber] = [0.00, 1.00, 0.00, 0.00]
        let endValues: [NSNumber] = [1.00, 1.00, 0.00, 1.00]
        
        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        let linear = CAMediaTimingFunction(name: .linear)
        let timingFuncs = [easeInOut, linear, easeInOut]
        
        let startAnim = CAKeyframeAnimation(keyPath: "strokeStart")
        startAnim.keyTimes = keyTimes
        startAnim.values = startValues
        startAnim.timingFunctions = timingFuncs
        startAnim.duration = cycleDuration
        startAnim.repeatCount = .infinity
        startAnim.calculationMode = .linear
        startAnim.isRemovedOnCompletion = false
        
        let endAnim = CAKeyframeAnimation(keyPath: "strokeEnd")
        endAnim.keyTimes = keyTimes
        endAnim.values = endValues
        endAnim.timingFunctions = timingFuncs
        endAnim.duration = cycleDuration
        endAnim.repeatCount = .infinity
        endAnim.calculationMode = .linear
        endAnim.isRemovedOnCompletion = false
        
        shapeLayer.add(startAnim, forKey: "strokeStartLoop")
        shapeLayer.add(endAnim, forKey: "strokeEndLoop")
    }
    
    private func stopLoopAnimation() {
        guard isAnimatingLoop else { return }
        isAnimatingLoop = false
        shapeLayer.removeAnimation(forKey: "strokeStartLoop")
        shapeLayer.removeAnimation(forKey: "strokeEndLoop")
    }
    
    override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = b
        shapeLayer.frame = b
        CATransaction.commit()
        
        // Rebuild path when dimensions change
        if b.width != cachedWidth || b.height != cachedHeight {
            cachedWidth = b.width
            cachedHeight = b.height
            rebuildEdgeToEdgePath(width: b.width, height: b.height)
        }
    }
    
    // MARK: - Dynamic Edge-to-Edge Stretched Path Generation (164 High-Density Bezier Segments)
    // Left straight line (x=0 to cursive start) + 164 cursive curves + right straight line (cursive end to x=width)
    private func rebuildEdgeToEdgePath(width: CGFloat, height: CGFloat) {
        // Allocated height is 40pt; cursive word scaled height is ~30pt
        let targetWordHeight = min(30.0, height * 0.75)
        let s = targetWordHeight / 414.94
        // The line thins with the word, or a small one fills in
        shapeLayer.lineWidth = max(1.3, 2.4 * targetWordHeight / 30.0)
        let scaledWordWidth = 779.66 * s
        
        // Word horizontally centered between window borders
        let wordStartX = (width - scaledWordWidth) / 2.0
        let wordCenterY = height / 2.0
        
        let xOffset = wordStartX - 522.67 * s
        let yOffset = wordCenterY - 584.47 * s
        
        let startY = 620.00 * s + yOffset
        let endY = 553.94 * s + yOffset
        
        let path = CGMutablePath()
        
        // 1. Straight line entering from the absolute left border of the window!
        path.move(to: CGPoint(x: 0, y: startY))
        path.addLine(to: CGPoint(x: wordStartX, y: startY))
        
        // 2. 164 high-density cursive "loading" cubic curves
        for seg in Self.denseMiddleCurves {
            let cp1 = CGPoint(x: seg.cp1.x * s + xOffset, y: seg.cp1.y * s + yOffset)
            let cp2 = CGPoint(x: seg.cp2.x * s + xOffset, y: seg.cp2.y * s + yOffset)
            let p3 = CGPoint(x: seg.p3.x * s + xOffset, y: seg.p3.y * s + yOffset)
            path.addCurve(to: p3, control1: cp1, control2: cp2)
        }
        
        // 3. Straight line extending all the way out through the absolute right border of the window!
        path.addLine(to: CGPoint(x: width, y: endY))
        
        // Flip Y to be upright in AppKit layer
        var flip = CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1.0, y: -1.0)
        if let flipped = path.copy(using: &flip) {
            shapeLayer.path = flipped
        }
    }
}

// MARK: - SwiftUI Representable Wrapper
struct SVGRefreshIndicatorView: NSViewRepresentable {
    var pullProgress: CGFloat
    var isRefreshing: Bool
    var colorScheme: AppThemeColor
    var tint: NSColor? = nil
    
    func makeNSView(context: Context) -> SVGRefreshIndicatorNSView {
        let view = SVGRefreshIndicatorNSView(frame: .zero)
        view.configure(progress: pullProgress, isRefreshing: isRefreshing, color: colorScheme, tint: tint)
        return view
    }
    
    func updateNSView(_ nsView: SVGRefreshIndicatorNSView, context: Context) {
        nsView.configure(progress: pullProgress, isRefreshing: isRefreshing, color: colorScheme, tint: tint)
    }
}

// MARK: - The App's Loading Animation
// The cursive "loading" from pull-to-refresh, for everything that waits. By default it runs edge to edge like the
// refresh line; give it a compact height where it sits inline, beside text or inside a button, and only the word shows.
struct LoadingIndicator: View {
    // False keeps the space but draws and animates nothing, for list footers that are only sometimes loading
    var active: Bool = true
    var compactHeight: CGFloat? = nil
    var tint: Color? = nil

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if let height = compactHeight {
            // Inline, beside a word or inside a button, the line drawing is too small to read; the system's own small
            // spinner is what a Mac shows there
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(tint)
                .opacity(active ? 1 : 0)
                .frame(width: height, height: height)
        } else {
            SVGRefreshIndicatorView(
                pullProgress: active ? 1 : 0,
                isRefreshing: active,
                colorScheme: theme.themeColor,
                tint: tint.map { NSColor($0) }
            )
            .frame(height: 40).frame(maxWidth: .infinity)
        }
    }
}
