//
//  AdBadgeView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI

/// Elegant Ad Badge conforming to Apple HIG & Tweetintosh Liquid Glass Aesthetic
struct AdBadgeView: View {
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var loc = LocalizationManager.shared
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "megaphone.fill")
                .font(.system(size: 8, weight: .bold))
            Text(loc.t("ad_badge"))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(theme.isLight ? Color.black.opacity(0.65) : Color.white.opacity(0.72))
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background {
            if theme.useLiquidGlass {
                if #available(macOS 26.0, *) {
                    Capsule()
                        .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                        .glassEffect(.regular, in: Capsule())
                        .overlay(
                            Capsule().stroke(theme.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                } else {
                    defaultBackground
                }
            } else {
                defaultBackground
            }
        }
        .help(loc.t("show_promoted_posts"))
    }
    
    private var defaultBackground: some View {
        Capsule()
            .fill(theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.12))
            .overlay(
                Capsule().stroke(ThemeManager.border, lineWidth: 0.6)
            )
    }
}
