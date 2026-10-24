//
//  SettingsView.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI

// MARK: - Glass Segmented Font Picker (High Contrast & Liquid Glass)
struct GlassSegmentedFontPicker: View {
    @Binding var selection: AppFontType
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var fontPickerNamespace
    
    var body: some View {
        HStack(spacing: 4) {
            segmentButton(type: .system, title: loc.t("font_system"))
            segmentButton(type: .mincho, title: loc.t("font_mincho"))
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
    
    private func segmentButton(type: AppFontType, title: String) -> some View {
        let isSelected = selection == type
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selection = type
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(theme.useLiquidGlass ? ThemeManager.accent : .white)
                }
                Text(title)
                    .font(type == .mincho ? .custom("Hiragino Mincho ProN", size: 12.5) : .system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.70))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    if theme.useLiquidGlass {
                        if #available(macOS 26.0, *) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(theme.useLiquidGlassTint ? ThemeManager.accent.opacity(0.24) : Color.white.opacity(0.18))
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                                )
                                .matchedGeometryEffect(id: "fontPickerSelection", in: fontPickerNamespace)
                        } else {
                            selectedBackground
                        }
                    } else {
                        selectedBackground
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var selectedBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.white.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
            .matchedGeometryEffect(id: "fontPickerSelection", in: fontPickerNamespace)
    }
}

// MARK: - Glass Capsule Toggle Style (Apple Liquid Glass HIG Switch)
struct GlassCapsuleToggleStyle: ToggleStyle {
    @ObservedObject var theme = ThemeManager.shared
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                // Background Track
                if theme.useLiquidGlass {
                    if #available(macOS 26.0, *) {
                        let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : Color.white
                        let glassStyle: Glass = theme.useLiquidGlassTint
                            ? .regular.tint(ThemeManager.accent.opacity(0.25))
                            : .regular
                        Capsule()
                            .fill(configuration.isOn ? tintColor.opacity(0.48) : Color.white.opacity(0.10))
                            .glassEffect(glassStyle, in: Capsule())
                            .frame(width: 44, height: 24)
                            .overlay(
                                Capsule()
                                    .stroke(configuration.isOn ? tintColor.opacity(0.7) : Color.white.opacity(0.22), lineWidth: 0.8)
                            )
                    } else {
                        fallbackTrack(isOn: configuration.isOn)
                    }
                } else {
                    fallbackTrack(isOn: configuration.isOn)
                }
                
                // Floating Glass Knob
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1.5)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
                    )
                    .padding(2)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
    
    private func fallbackTrack(isOn: Bool) -> some View {
        Capsule()
            .fill(
                isOn
                    ? (theme.useLiquidGlassTint ? ThemeManager.accent.opacity(0.58) : ThemeManager.accent.opacity(0.45))
                    : Color.white.opacity(0.12)
            )
            .frame(width: 44, height: 24)
            .overlay(
                Capsule()
                    .stroke(
                        isOn
                            ? (theme.useLiquidGlassTint ? ThemeManager.accent.opacity(0.75) : ThemeManager.accent.opacity(0.60))
                            : Color.white.opacity(0.20),
                        lineWidth: 0.8
                    )
            )
    }
}

// MARK: - Glass Dropdown Menu Picker (Apple HIG Glass PopUp)
struct GlassDropdownPicker<T: Hashable>: View {
    @Binding var selection: T
    var options: [(T, String)]
    var iconProvider: ((T) -> AnyView)? = nil
    @ObservedObject var theme = ThemeManager.shared
    
    var body: some View {
        Menu {
            ForEach(options, id: \.0) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selection = item.0
                    }
                } label: {
                    HStack {
                        Text(item.1)
                        if selection == item.0 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let icon = iconProvider?(selection) {
                    icon
                }
                Text(currentTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.50))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if theme.useLiquidGlass {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                    } else {
                        defaultMenuBackground
                    }
                } else {
                    defaultMenuBackground
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var currentTitle: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }
    
    private var defaultMenuBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
    }
}

// MARK: - SettingsView Main Interface
struct SettingsView: View {
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    
    var onSignOut: () -> Void
    var onClearCache: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Language Section
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t("language"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                
                if theme.useLiquidGlass {
                    GlassDropdownPicker(
                        selection: $loc.currentLanguage,
                        options: AppLanguage.allCases.map { ($0, $0.displayName) }
                    )
                } else {
                    Picker("", selection: $loc.currentLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(PopUpButtonPickerStyle())
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .background(cardBackground)
            
            // 2. Typography & Visual Section
            VStack(alignment: .leading, spacing: 14) {
                Text(loc.t("typography"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                
                // High-contrast Font Selector (Fixes unreadable black Hiragino Mincho text)
                GlassSegmentedFontPicker(selection: $theme.fontType)
                
                // Liquid Glass Switches (Apple Official HIG Glass Switches)
                if theme.useLiquidGlass {
                    Toggle(loc.t("use_liquid_glass"), isOn: $theme.useLiquidGlass.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                    
                    Toggle(loc.t("tint_colour"), isOn: $theme.useLiquidGlassTint)
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                        .padding(.leading, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Toggle(loc.t("use_liquid_glass"), isOn: $theme.useLiquidGlass.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(.switch)
                        .tint(ThemeManager.accent)
                        .foregroundColor(ThemeManager.primaryText)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.t("theme_colour"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeManager.secondaryText)
                    
                    if theme.useLiquidGlass {
                        GlassDropdownPicker(
                            selection: $theme.themeColor,
                            options: AppThemeColor.allCases.map { ($0, loc.t($0.displayNameKey)) },
                            iconProvider: { color in
                                AnyView(
                                    Circle()
                                        .fill(color.accentColor)
                                        .frame(width: 10, height: 10)
                                )
                            }
                        )
                    } else {
                        Picker("", selection: $theme.themeColor) {
                            ForEach(AppThemeColor.allCases) { color in
                                Text(loc.t(color.displayNameKey)).tag(color)
                            }
                        }
                        .pickerStyle(PopUpButtonPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(cardBackground)
            
            // 3. Data & Account Management
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: onClearCache) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                            Text(loc.t("clear_cache"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Color.white.opacity(0.92))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if theme.useLiquidGlass {
                                if #available(macOS 26.0, *) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                        .glassEffect(.regular, in: Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                                        )
                                } else {
                                    defaultClearCacheBackground
                                }
                            } else {
                                defaultClearCacheBackground
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Button(action: onSignOut) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                            Text(loc.t("sign_out"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Color.white.opacity(0.95))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if theme.useLiquidGlass {
                                if #available(macOS 26.0, *) {
                                    Capsule()
                                        .fill(Color.red.opacity(0.25))
                                        .glassEffect(.regular.tint(Color.red.opacity(0.3)), in: Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.red.opacity(0.45), lineWidth: 0.8)
                                        )
                                } else {
                                    defaultSignOutBackground
                                }
                            } else {
                                defaultSignOutBackground
                            }
                        }
                        .contentShape(Capsule())
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
        .padding(20)
        .frame(width: 480, height: 420)
        .background(ThemeManager.background)
    }
    
    private var defaultClearCacheBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
    }
    
    private var defaultSignOutBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.red.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red.opacity(0.40), lineWidth: 0.8)
            )
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .glassEffect(theme.useLiquidGlassTint ? .regular.tint(ThemeManager.accent.opacity(0.12)) : .regular, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.10).opacity(0.60))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeManager.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ThemeManager.border, lineWidth: 0.5)
                )
        }
    }
}
