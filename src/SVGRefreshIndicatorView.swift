//
//  SVGRefreshIndicatorView.swift
//  MaX - Headless Data-driven Client
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
    
    // Cached path geometry
    private var cachedWidth: CGFloat = 0
    private var cachedHeight: CGFloat = 0
    private var cursiveEndFraction: CGFloat = 0.8
    
    // Middle 41 cubic curves of cursive "loading"
    private static let middleCurves: [CurveSegment] = {
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
        return Array(segs[1..<(segs.count - 1)])
    }()
    
    private static let keyTimes: [NSNumber] = [
        0.00, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
        0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00
    ]
    private static let strokeStartValues: [NSNumber] = [
        0.0000, 0.0136, 0.0272, 0.0409, 0.0545, 0.0681, 0.0817, 0.0953, 0.1090, 0.1226, 0.1362,
        0.1498, 0.1634, 0.1770, 0.1907, 0.2043, 0.3484, 0.5113, 0.6742, 0.8371, 1.0000
    ]
    private static let strokeEndValues: [NSNumber] = [
        0.0000, 0.1607, 0.3215, 0.4822, 0.6430, 0.8037, 0.8226, 0.8353, 0.8480, 0.8606, 0.8733,
        0.8860, 0.8986, 0.9113, 0.9240, 0.9367, 0.9493, 0.9620, 0.9747, 0.9873, 1.0000
    ]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
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
        gradientLayer.colors = colorScheme.gradientColors.map { $0.cgColor }
    }
    
    func configure(progress: CGFloat, isRefreshing: Bool, color: AppThemeColor) {
        let colorChanged = (self.colorScheme != color)
        self.pullProgress = progress
        self.isRefreshing = isRefreshing
        self.colorScheme = color
        
        if colorChanged {
            updateGradientColors()
        }
        
        if isRefreshing {
            startLoopAnimationIfNeeded()
        } else {
            stopLoopAnimation()
            // During pull down: Line extends out from the left edge (X = 0) towards the cursive word
            let targetEnd = min(cursiveEndFraction, max(0.0, progress * cursiveEndFraction))
            shapeLayer.strokeStart = 0.0
            shapeLayer.strokeEnd = targetEnd
        }
    }
    
    private func startLoopAnimationIfNeeded() {
        guard !isAnimatingLoop else { return }
        isAnimatingLoop = true
        
        // Seamless transition:
        // Pick up directly from keyTime 0.25 (timeOffset = 0.50s in a 2.0s cycle),
        // where strokeEnd is ~0.8037 and strokeStart is ~0.0681.
        // This finishes the current stroke smoothly out through the right edge before repeating,
        // without destroying or resetting progress to 0.
        let initialOffset: CFTimeInterval = 0.50
        
        let startAnim = CAKeyframeAnimation(keyPath: "strokeStart")
        startAnim.keyTimes = Self.keyTimes
        startAnim.values = Self.strokeStartValues
        startAnim.duration = 2.0
        startAnim.timeOffset = initialOffset
        startAnim.repeatCount = .infinity
        startAnim.calculationMode = .linear
        startAnim.isRemovedOnCompletion = false
        
        let endAnim = CAKeyframeAnimation(keyPath: "strokeEnd")
        endAnim.keyTimes = Self.keyTimes
        endAnim.values = Self.strokeEndValues
        endAnim.duration = 2.0
        endAnim.timeOffset = initialOffset
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
        
        gradientLayer.frame = b
        shapeLayer.frame = b
        
        // Rebuild path only when size changes
        if b.width != cachedWidth || b.height != cachedHeight {
            cachedWidth = b.width
            cachedHeight = b.height
            rebuildEdgeToEdgePath(width: b.width, height: b.height)
        }
    }
    
    // MARK: - Dynamic Edge-to-Edge Stretched Path Generation
    private func rebuildEdgeToEdgePath(width: CGFloat, height: CGFloat) {
        // Cursive word intrinsic height is 414.94, width is 779.66
        let targetWordHeight = min(36.0, height * 0.72)
        let s = targetWordHeight / 414.94
        let scaledWordWidth = 779.66 * s
        
        // Word horizontally centered
        let wordStartX = (width - scaledWordWidth) / 2.0
        let wordCenterY = height / 2.0
        
        let xOffset = wordStartX - 522.67 * s
        let yOffset = wordCenterY - 584.47 * s
        
        let startY = 620.00 * s + yOffset
        let endY = 552.00 * s + yOffset
        
        let path = CGMutablePath()
        
        // 1. Start from the absolute left border of the window!
        path.move(to: CGPoint(x: 0, y: startY))
        
        // 2. Straight line leading to the cursive word start
        path.addLine(to: CGPoint(x: wordStartX, y: startY))
        
        // 3. Middle cursive "loading" curves
        for seg in Self.middleCurves {
            let cp1 = CGPoint(x: seg.cp1.x * s + xOffset, y: seg.cp1.y * s + yOffset)
            let cp2 = CGPoint(x: seg.cp2.x * s + xOffset, y: seg.cp2.y * s + yOffset)
            let p3 = CGPoint(x: seg.p3.x * s + xOffset, y: seg.p3.y * s + yOffset)
            path.addCurve(to: p3, control1: cp1, control2: cp2)
        }
        
        // 4. Straight line extending all the way to the absolute right border of the window!
        path.addLine(to: CGPoint(x: width, y: endY))
        
        // Flip Y to be upright in AppKit layer
        var flip = CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1.0, y: -1.0)
        if let flipped = path.copy(using: &flip) {
            shapeLayer.path = flipped
        }
        
        // Compute path length fractions
        let cursiveLength = 3165.16 * s
        let totalLength = (width - scaledWordWidth) + cursiveLength
        let wordEndLen = wordStartX + cursiveLength
        self.cursiveEndFraction = min(0.95, max(0.65, wordEndLen / max(1.0, totalLength)))
    }
}

// MARK: - SwiftUI Representable Wrapper
struct SVGRefreshIndicatorView: NSViewRepresentable {
    var pullProgress: CGFloat
    var isRefreshing: Bool
    var colorScheme: AppThemeColor
    
    func makeNSView(context: Context) -> SVGRefreshIndicatorNSView {
        let view = SVGRefreshIndicatorNSView(frame: .zero)
        view.configure(progress: pullProgress, isRefreshing: isRefreshing, color: colorScheme)
        return view
    }
    
    func updateNSView(_ nsView: SVGRefreshIndicatorNSView, context: Context) {
        nsView.configure(progress: pullProgress, isRefreshing: isRefreshing, color: colorScheme)
    }
}
