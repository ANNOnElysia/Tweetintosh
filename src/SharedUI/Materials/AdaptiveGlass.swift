//
//  AdaptiveGlass.swift
//  Tweetintosh
//
//  The glass and frosted surfaces shared by the shell, sheets and feature pages.
//

import SwiftUI
import AppKit

// MARK: - Native AppKit Visual Effect View (True macOS Translucent Gaussian Blur)
final class NonInteractiveVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Transparent to all mouse clicks so SwiftUI buttons receive events immediately
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NonInteractiveVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Adaptive Glass Modifier (Liquid Glass Mode vs Frosted Glass Off Mode)
// Every Liquid Glass surface goes through here. It is Apple's glass as the HIG describes it, with no clarity control of
// the app's own: how clear or tinted the glass looks, and Reduce Transparency, are the user's choices in System Settings,
// which the system glass already follows.
@available(macOS 26.0, *)
private struct TweetGlassModifier<S: Shape>: ViewModifier {
    var glass: Glass
    var shape: S

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: shape)
    }
}

extension View {
    @available(macOS 26.0, *)
    func tweetGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        modifier(TweetGlassModifier(glass: glass, shape: shape))
    }
}

struct AdaptiveGlassModifier<S: Shape>: ViewModifier {
    var isLiquid: Bool
    var shape: S
    // Clear variant, so content behind stays visible (top tab switcher)
    var isClear: Bool = false
    // Interactive glass answers a press itself, which suits glass that is a control. A bar or panel holding other
    // controls passes false: on a touch screen its own response to a finger took the touch from the tab or button on it.
    var isInteractive: Bool = true
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        if isLiquid {
            if #available(macOS 26.0, *) {
                // Mode A: Native Liquid Glass (SwiftUI macOS 26+ native API)
                let base: Glass = isClear ? .clear : .regular
                let tinted: Glass = theme.useLiquidGlassTint
                    ? base.tint(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.16))
                    : base
                let glassStyle: Glass = isInteractive ? tinted.interactive() : tinted

                // Nothing painted behind or around it: a fill sits between the glass and what it refracts and turns it
                // milky, and the system glass already draws its own edge and shadow
                content.tweetGlass(glassStyle, in: shape)
            } else {
                fallbackFrostedGlass(content: content)
            }
        } else {
            // Mode B: Liquid Glass Disabled - Pure High-grade Gaussian Blur (VisualEffectView)
            fallbackFrostedGlass(content: content)
        }
    }

    @ViewBuilder
    private func fallbackFrostedGlass(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBackground(
                        material: theme.isLight ? .headerView : .sidebar,
                        blendingMode: .withinWindow
                    )
                    (theme.isLight ? Color.white.opacity(0.72) : Color(white: 0.08).opacity(0.42))
                }
                .clipShape(shape)
            )
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: theme.isLight ? [
                                Color(hex: "#DED9CB").opacity(0.85),
                                Color(hex: "#ECE8DC").opacity(0.60),
                                Color.white.opacity(0.90)
                            ] : [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: Color.black.opacity(theme.isLight ? 0.08 : 0.35),
                radius: theme.isLight ? 10 : 14,
                x: 0,
                y: theme.isLight ? 3 : 5
            )
    }
}
