//
//  SettingsView.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI

// MARK: - Glass Segmented Appearance Picker (Dark / Light / System)
struct GlassSegmentedAppearancePicker: View {
    @Binding var selection: AppThemeAppearance
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var appearancePickerNamespace
    
    var body: some View {
        HStack(spacing: 4) {
            segmentButton(type: .dark, title: loc.t("theme_dark"), icon: "moon.fill")
            segmentButton(type: .light, title: loc.t("theme_light"), icon: "sun.max.fill")
            segmentButton(type: .system, title: loc.t("theme_system"), icon: "circle.lefthalf.filled")
        }
        .padding(3.5)
        .background(
            Capsule()
                .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
    
    private func segmentButton(type: AppThemeAppearance, title: String, icon: String) -> some View {
        let isSelected = selection == type
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selection = type
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? (theme.useLiquidGlass ? ThemeManager.accent : (theme.isLight ? ThemeManager.accent : .white)) : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.60)))
                Text(title)
                    .font(theme.appFont(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? (theme.isLight ? ThemeManager.primaryText : .white) : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.70)))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    if theme.useLiquidGlass {
                        if #available(macOS 26.0, *) {
                            Capsule()
                                .fill(theme.useLiquidGlassTint ? ThemeManager.accent.opacity(theme.isLight ? 0.16 : 0.24) : (theme.isLight ? Color.white : Color.white.opacity(0.18)))
                                .tweetGlass(.regular, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.25), lineWidth: 0.8)
                                )
                                .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.2), radius: 3, x: 0, y: 1)
                                .matchedGeometryEffect(id: "appearanceSelection", in: appearancePickerNamespace)
                        } else {
                            selectedBackground
                        }
                    } else {
                        selectedBackground
                    }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var selectedBackground: some View {
        Capsule()
            .fill(theme.isLight ? Color.white : Color.white.opacity(0.16))
            .overlay(
                Capsule()
                    .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.25), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.2), radius: 3, x: 0, y: 1)
            .matchedGeometryEffect(id: "appearanceSelection", in: appearancePickerNamespace)
    }
}

// MARK: - Glass Segmented Tone Picker (Mild / Minimalism)
struct GlassSegmentedTonePicker: View {
    @Binding var selection: AppThemeTone
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @Namespace private var tonePickerNamespace
    
    var body: some View {
        HStack(spacing: 4) {
            segmentButton(type: .mild, title: loc.t("theme_tone_mild"), icon: "leaf.fill")
            segmentButton(type: .minimalism, title: loc.t("theme_tone_minimalism"), icon: "circle.fill")
        }
        .padding(3.5)
        .background(
            Capsule()
                .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
    
    private func segmentButton(type: AppThemeTone, title: String, icon: String) -> some View {
        let isSelected = selection == type
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selection = type
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? (theme.useLiquidGlass ? ThemeManager.accent : (theme.isLight ? ThemeManager.accent : .white)) : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.60)))
                Text(title)
                    .font(theme.appFont(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? (theme.isLight ? ThemeManager.primaryText : .white) : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.70)))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    if theme.useLiquidGlass {
                        if #available(macOS 26.0, *) {
                            Capsule()
                                .fill(theme.useLiquidGlassTint ? ThemeManager.accent.opacity(theme.isLight ? 0.16 : 0.24) : (theme.isLight ? Color.white : Color.white.opacity(0.18)))
                                .tweetGlass(.regular, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.25), lineWidth: 0.8)
                                )
                                .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.2), radius: 3, x: 0, y: 1)
                                .matchedGeometryEffect(id: "toneSelection", in: tonePickerNamespace)
                        } else {
                            selectedBackground
                        }
                    } else {
                        selectedBackground
                    }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var selectedBackground: some View {
        Capsule()
            .fill(theme.isLight ? Color.white : Color.white.opacity(0.16))
            .overlay(
                Capsule()
                    .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.25), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.2), radius: 3, x: 0, y: 1)
            .matchedGeometryEffect(id: "toneSelection", in: tonePickerNamespace)
    }
}

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
        .padding(3.5)
        .background(
            Capsule()
                .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12), lineWidth: 0.8)
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
                        .foregroundColor(theme.useLiquidGlass ? ThemeManager.accent : (theme.isLight ? ThemeManager.accent : .white))
                }
                Text(title)
                    .font(type == .mincho ? .custom(theme.activeSerifFontName, size: 12.5) : .system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? (theme.isLight ? ThemeManager.primaryText : .white) : (theme.isLight ? ThemeManager.secondaryText : Color.white.opacity(0.70)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    if theme.useLiquidGlass {
                        if #available(macOS 26.0, *) {
                            Capsule()
                                .fill(theme.useLiquidGlassTint ? ThemeManager.accent.opacity(theme.isLight ? 0.16 : 0.24) : (theme.isLight ? Color.white : Color.white.opacity(0.18)))
                                .tweetGlass(.regular, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.25), lineWidth: 0.8)
                                )
                                .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.2), radius: 3, x: 0, y: 1)
                                .matchedGeometryEffect(id: "fontPickerSelection", in: fontPickerNamespace)
                        } else {
                            selectedBackground
                        }
                    } else {
                        selectedBackground
                    }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var selectedBackground: some View {
        Capsule()
            .fill(theme.isLight ? Color.white : Color.white.opacity(0.16))
            .overlay(
                Capsule()
                    .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.25), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(theme.isLight ? 0.08 : 0.2), radius: 3, x: 0, y: 1)
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
                        let tintColor = theme.useLiquidGlassTint ? ThemeManager.accent : (theme.isLight ? Color.black : Color.white)
                        let glassStyle: Glass = theme.useLiquidGlassTint
                            ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.20 : 0.25))
                            : .regular
                        Capsule()
                            .fill(configuration.isOn ? (theme.useLiquidGlassTint ? tintColor.opacity(0.70) : tintColor.opacity(0.48)) : (theme.isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.10)))
                            .tweetGlass(glassStyle, in: Capsule())
                            .frame(width: 44, height: 24)
                            .overlay(
                                Capsule()
                                    .stroke(configuration.isOn ? tintColor.opacity(0.7) : (theme.isLight ? Color.black.opacity(0.15) : Color.white.opacity(0.22)), lineWidth: 0.8)
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
                    .shadow(color: Color.black.opacity(theme.isLight ? 0.20 : 0.35), radius: 3, x: 0, y: 1.5)
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
                    ? (theme.useLiquidGlassTint ? ThemeManager.accent.opacity(0.85) : ThemeManager.accent.opacity(0.70))
                    : (theme.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.12))
            )
            .frame(width: 44, height: 24)
            .overlay(
                Capsule()
                    .stroke(
                        isOn
                            ? (theme.useLiquidGlassTint ? ThemeManager.accent.opacity(0.90) : ThemeManager.accent.opacity(0.80))
                            : (theme.isLight ? Color.black.opacity(0.16) : Color.white.opacity(0.20)),
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
                    .font(theme.appFont(size: 13, weight: .medium))
                    .foregroundColor(theme.isLight ? ThemeManager.primaryText : .white)
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.isLight ? ThemeManager.tertiaryText : Color.white.opacity(0.50))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if theme.useLiquidGlass {
                    if #available(macOS 26.0, *) {
                        Capsule()
                            .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                            .tweetGlass(.regular, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                    } else {
                        defaultMenuBackground
                    }
                } else {
                    defaultMenuBackground
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var currentTitle: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }
    
    private var defaultMenuBackground: some View {
        Capsule()
            .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
            .overlay(
                Capsule()
                    .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.14), lineWidth: 0.8)
            )
    }
}

// MARK: - Settings Close Button (Top-Right "小麻叉")
struct SettingsCloseButtonStyle: ButtonStyle {
    @ObservedObject var theme = ThemeManager.shared
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if theme.useLiquidGlass {
                    if #available(macOS 26.0, *) {
                        Circle()
                            .fill(configuration.isPressed ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                            .tweetGlass(.regular, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(configuration.isPressed ? Color.white.opacity(0.35) : Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                    } else {
                        defaultCircleBackground(isPressed: configuration.isPressed)
                    }
                } else {
                    defaultCircleBackground(isPressed: configuration.isPressed)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
    
    private func defaultCircleBackground(isPressed: Bool) -> some View {
        Circle()
            .fill(
                isPressed
                    ? (theme.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.20))
                    : (theme.isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.10))
            )
            .overlay(
                Circle()
                    .stroke(
                        theme.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.14),
                        lineWidth: 0.6
                    )
            )
    }
}

struct SettingsCloseButton: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(ThemeManager.secondaryText)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(SettingsCloseButtonStyle())
        .keyboardShortcut(.escape, modifiers: [])
        .help("Esc")
    }
}

// MARK: - SettingsView Main Interface
struct SettingsView: View {
    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var mediaCache = MediaCacheManager.shared
    
    @ObservedObject var accountManager = AccountManager.shared
    
    var onSignOut: () -> Void
    var onSwitchAccount: (String) -> Void
    var onAddAccount: () -> Void
    var onClearCache: () -> Void
    var onClose: () -> Void = {}
    
    // Accounts: tap one to switch to it, or add another
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("accounts"))
                .font(theme.appFont(size: 13, weight: .semibold))
                .foregroundColor(ThemeManager.secondaryText)
            
            ForEach(accountManager.accounts) { account in
                let isActive = account.id == accountManager.active?.id
                Button {
                    onSwitchAccount(account.id)
                } label: {
                    HStack(spacing: 10) {
                        Group {
                            if let url = account.avatarUrl {
                                CachedAsyncImage(urlString: url, targetSize: CGSize(width: 32, height: 32))
                            } else {
                                Circle().fill(ThemeManager.secondaryText.opacity(0.25))
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.name.isEmpty ? loc.t("account_signed_in") : account.name)
                                .font(theme.appFont(size: 13, weight: .semibold))
                                .foregroundColor(ThemeManager.primaryText)
                                .lineLimit(1)
                            if !account.screenName.isEmpty {
                                Text("@\(account.screenName)")
                                    .font(theme.appFont(size: 11.5))
                                    .foregroundColor(ThemeManager.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(ThemeManager.accent)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(isActive ? "" : loc.t("switch_account"))
            }
            
            Button(action: onAddAccount) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                    Text(loc.t("add_account"))
                        .font(theme.appFont(size: 13, weight: .medium))
                }
                .foregroundColor(ThemeManager.accent)
                .padding(.vertical, 4)
                .contentShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(14)
        .background(cardBackground)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar: Title on left, Close ("小麻叉") on right
            HStack(alignment: .center) {
                Text(loc.t("settings"))
                    .font(theme.appFont(size: 16, weight: .bold))
                    .foregroundColor(ThemeManager.primaryText)
                
                Spacer()
                
                SettingsCloseButton(action: onClose)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(ThemeManager.background)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 0. Accounts
                    accountsSection
            
            // 1. Language Section
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.t("language"))
                    .font(theme.appFont(size: 13, weight: .semibold))
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
            .padding(14)
            .background(cardBackground)
            
            // 2. Appearance Section (Merged Appearance & Typography)
            VStack(alignment: .leading, spacing: 12) {
                Text(loc.t("theme_appearance"))
                    .font(theme.appFont(size: 13, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                
                // Dark / Light / System
                GlassSegmentedAppearancePicker(selection: $theme.appearance)
                
                // Mild / Minimalism Tone Switcher
                GlassSegmentedTonePicker(selection: $theme.themeTone)
                
                Divider()
                    .overlay(ThemeManager.divider)
                    .padding(.vertical, 2)
                
                // Typography & Font
                Text(loc.t("typography"))
                    .font(theme.appFont(size: 12, weight: .medium))
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
                        .font(theme.appFont(size: 12, weight: .medium))
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
                .padding(.top, 2)
            }
            .padding(14)
            .background(cardBackground)
            
            // 4. Content & Display (内容与展示)
            VStack(alignment: .leading, spacing: 10) {
                Text(loc.t("content_settings"))
                    .font(theme.appFont(size: 13, weight: .semibold))
                    .foregroundColor(ThemeManager.secondaryText)
                
                if theme.useLiquidGlass {
                    Toggle(loc.t("show_promoted_posts"), isOn: $theme.showPromotedPosts.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                } else {
                    Toggle(loc.t("show_promoted_posts"), isOn: $theme.showPromotedPosts.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(.switch)
                        .tint(ThemeManager.accent)
                        .foregroundColor(ThemeManager.primaryText)
                }
                
                Text(loc.t("show_promoted_posts_desc"))
                    .font(theme.appFont(size: 11))
                    .foregroundColor(ThemeManager.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                
                if theme.useLiquidGlass {
                    Toggle(loc.t("autoplay_media"), isOn: $theme.autoplayMedia.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                } else {
                    Toggle(loc.t("autoplay_media"), isOn: $theme.autoplayMedia.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(.switch)
                        .tint(ThemeManager.accent)
                        .foregroundColor(ThemeManager.primaryText)
                }
                
                Text(loc.t("autoplay_media_desc"))
                    .font(theme.appFont(size: 11))
                    .foregroundColor(ThemeManager.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
            .padding(14)
            .background(cardBackground)
            
            // 5. Data & Account Management
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: onClearCache) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                            Text(mediaCache.formattedCacheSize == "0 B" ? loc.t("clear_cache") : "\(loc.t("clear_cache")) (\(mediaCache.formattedCacheSize))")
                                .font(theme.appFont(size: 13, weight: .medium))
                        }
                        .foregroundColor(theme.isLight ? ThemeManager.primaryText : Color.white.opacity(0.92))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if theme.useLiquidGlass {
                                if #available(macOS 26.0, *) {
                                    Capsule()
                                        .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
                                        .tweetGlass(.regular, in: Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(theme.isLight ? Color(hex: "#DED9CB") : Color.white.opacity(0.20), lineWidth: 0.8)
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
                                .font(theme.appFont(size: 13, weight: .medium))
                        }
                        .foregroundColor(Color.white.opacity(0.95))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if theme.useLiquidGlass {
                                if #available(macOS 26.0, *) {
                                    Capsule()
                                        .fill(Color.red.opacity(0.35))
                                        .tweetGlass(.regular.tint(Color.red.opacity(0.3)), in: Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.red.opacity(0.55), lineWidth: 0.8)
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
            .padding(14)
            .background(cardBackground)
            
            Spacer(minLength: 8)
            
            // Footer
            HStack {
                Spacer()
                Button(loc.t("license_agreement")) { LicenseAgreementWindow.show() }
                    .buttonStyle(.link)
                    .font(theme.appFont(size: 12))
                Spacer()
            }
            HStack {
                Spacer()
                Text("Tweetintosh v\(AppVersion.short) (Headless Native Swift)")
                    .font(theme.appFont(size: 11))
                    .foregroundColor(ThemeManager.tertiaryText)
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
        }
        }
        .frame(width: 480, height: 860)
        .background(ThemeManager.background)
    }
    
    private var defaultClearCacheBackground: some View {
        Capsule()
            .fill(theme.isLight ? Color.black.opacity(0.04) : Color.white.opacity(0.08))
            .overlay(
                Capsule()
                    .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.16), lineWidth: 0.8)
            )
    }
    
    private var defaultSignOutBackground: some View {
        Capsule()
            .fill(Color.red.opacity(0.30))
            .overlay(
                Capsule()
                    .stroke(Color.red.opacity(0.48), lineWidth: 0.8)
            )
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if theme.useLiquidGlass {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.isLight ? Color.white.opacity(0.60) : Color.white.opacity(0.04))
                    .tweetGlass(theme.useLiquidGlassTint ? .regular.tint(ThemeManager.accent.opacity(theme.isLight ? 0.08 : 0.12)) : .regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.14), lineWidth: 0.8)
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.isLight ? ThemeManager.cardBackground : Color(white: 0.10).opacity(0.60))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.isLight ? ThemeManager.border : Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ThemeManager.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ThemeManager.border, lineWidth: 0.5)
                )
        }
    }
}
