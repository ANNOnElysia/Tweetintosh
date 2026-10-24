//
//  SettingsView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    
    var onSignOut: () -> Void
    var onClearCache: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text(loc.t("settings"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.bottom, 4)
            
            // 1. Language Section
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t("language"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                
                Picker("", selection: $loc.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(PopUpButtonPickerStyle())
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(cardBackground)
            
            // 2. Typography & Visual Section
            VStack(alignment: .leading, spacing: 14) {
                Text(loc.t("typography"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                
                Picker("", selection: $theme.fontType) {
                    Text(loc.t("font_system")).tag(AppFontType.system)
                    Text(loc.t("font_mincho")).tag(AppFontType.mincho)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                // Native System Toggles with Liquid Glass / Vibrant Theme Adaptation
                Toggle(loc.t("use_liquid_glass"), isOn: $theme.useLiquidGlass.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                    .toggleStyle(.switch)
                    .tint(ThemeManager.accent)
                    .foregroundColor(ThemeManager.primaryText)
                
                if theme.useLiquidGlass {
                    Toggle(loc.t("tint_colour"), isOn: $theme.useLiquidGlassTint)
                        .toggleStyle(.switch)
                        .tint(ThemeManager.accent)
                        .foregroundColor(ThemeManager.primaryText)
                        .padding(.leading, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.t("theme_colour"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeManager.secondaryText)
                    
                    Picker("", selection: $theme.themeColor) {
                        ForEach(AppThemeColor.allCases) { color in
                            Text(loc.t(color.displayNameKey)).tag(color)
                        }
                    }
                    .pickerStyle(PopUpButtonPickerStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(cardBackground)
            
            // 3. Data & Account Management
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: onClearCache) {
                        Text(loc.t("clear_cache"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.92))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Button(action: onSignOut) {
                        Text(loc.t("sign_out"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.38, blue: 0.38))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.red.opacity(0.24), lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(12)
            .background(cardBackground)
            
            Spacer()
            
            // Footer
            HStack {
                Spacer()
                Text("MaX v2.0 (Headless Native Swift)")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeManager.tertiaryText)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 480, height: 410)
        .background(ThemeManager.background)
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if theme.useLiquidGlass {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.08).opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(ThemeManager.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ThemeManager.border, lineWidth: 0.5)
                )
        }
    }
}
