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
            .contentShape(Rectangle())
        }
        .buttonStyle(.target)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.target)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.target)
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
// Every switch in Settings: the system switch, kept at the trailing edge of its row (on its own, macOS puts it right
// after the label). It is the system control so it takes on Liquid Glass when pressed, as the HIG has sliders and
// toggles do; a drawn imitation cannot match the system's glass.
struct GlassCapsuleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            ThemedSwitch(isOn: configuration.$isOn)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "1" : "0")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

// The system switch, on in the app's theme colour as the HIG allows. It watches the theme itself, so a new colour
// reaches it at once, and is rebuilt for each colour because the AppKit switch underneath keeps the tint it was made
// with.
private struct ThemedSwitch: View {
    @Binding var isOn: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .tint(ThemeManager.accent)
            .labelsHidden()
            .accessibilityHidden(true)
            .id(theme.themeColor)
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
            .padding(5)
            .contentShape(Rectangle())
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
    @ObservedObject private var theme = ThemeManager.shared
    
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
        // The style grows the button to the 36-point target around its circle; this takes the growth back
        .padding(-5)
    }
}

// MARK: - SettingsView Main Interface
struct SettingsView: View {
    private static let headerHeight: CGFloat = 54

    @ObservedObject var loc = LocalizationManager.shared
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var mediaCache = MediaCacheManager.shared
    
    @ObservedObject var accountManager = AccountManager.shared
    @ObservedObject private var translation = TranslationSettingsManager.shared
    @State private var showModelPicker = false
    @State private var modelSearchQuery = ""
    private let cacheCleanup = CacheCleanup.shared
    private let updates = UpdateManager.shared
    
    var onSignOut: () -> Void
    var onSwitchAccount: (String) -> Void
    var onAddAccount: () -> Void
    var onClearCache: () -> Void
    var onClose: () -> Void = {}
    
    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("settings_translation"))
                .font(theme.appFont(size: 13, weight: .semibold))
                .foregroundColor(ThemeManager.secondaryText)

            HStack {
                Text(loc.t("translation_engine"))
                    .font(theme.appFont(size: 13))
                    .foregroundColor(ThemeManager.primaryText)
                Spacer()
                Picker("", selection: $translation.engine.animation(.easeInOut(duration: 0.2))) {
                    ForEach(TranslationEngine.allCases) { engine in
                        Text(engine.localizedTitle).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack {
                Text(loc.t("translation_target_language"))
                    .font(theme.appFont(size: 13))
                    .foregroundColor(ThemeManager.primaryText)
                Spacer()
                Picker("", selection: $translation.targetLanguage) {
                    Text(loc.t("translation_follow_app")).tag(Optional<AppLanguage>.none)
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(Optional(lang))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if translation.engine == .byok {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.t("translation_base_url"))
                            .font(theme.appFont(size: 11.5, weight: .medium))
                            .foregroundColor(ThemeManager.secondaryText)
                        TextField("https://api.openai.com/v1", text: $translation.apiBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(theme.appFont(size: 12.5))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.t("translation_api_key"))
                            .font(theme.appFont(size: 11.5, weight: .medium))
                            .foregroundColor(ThemeManager.secondaryText)
                        SecureField("sk-...", text: $translation.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(theme.appFont(size: 12.5))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.t("translation_model"))
                            .font(theme.appFont(size: 11.5, weight: .medium))
                            .foregroundColor(ThemeManager.secondaryText)
                        HStack(spacing: 8) {
                            TextField("gpt-4o-mini", text: $translation.modelName)
                                .textFieldStyle(.roundedBorder)
                                .font(theme.appFont(size: 12.5))

                            Button {
                                showModelPicker.toggle()
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(ThemeManager.secondaryText)
                                    .frame(width: 24, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                                modelPickerPopover
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await translation.verifyAndFetchModels() }
                        } label: {
                            HStack(spacing: 5) {
                                if translation.isVerifying {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text(loc.t("translation_verifying"))
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11, weight: .medium))
                                    Text(loc.t("translation_verify_fetch"))
                                }
                            }
                            .font(theme.appFont(size: 12, weight: .medium))
                        }
                        .disabled(translation.isVerifying)

                        if let status = translation.verificationStatus {
                            switch status {
                            case .success(let msg):
                                Label(msg, systemImage: "checkmark.circle.fill")
                                    .font(theme.appFont(size: 11.5))
                                    .foregroundColor(Color(hex: "#00BA7C"))
                                    .lineLimit(1)
                            case .failure(let msg):
                                Label(msg, systemImage: "exclamationmark.triangle.fill")
                                    .font(theme.appFont(size: 11.5))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 2)

                    Text(loc.t("translation_byok_hint"))
                        .font(theme.appFont(size: 11.5))
                        .foregroundColor(ThemeManager.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var modelPickerPopover: some View {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let presets = translation.activeRecommendedModels.filter {
            query.isEmpty || $0.id.lowercased().contains(query) || $0.label.lowercased().contains(query)
        }
        let fetched = translation.fetchedModels.filter {
            query.isEmpty || $0.lowercased().contains(query)
        }

        return VStack(spacing: 0) {
            if translation.fetchedModels.count > 8 {
                TextField("Filter…", text: $modelSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(theme.appFont(size: 12))
                    .padding(8)
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !presets.isEmpty {
                        Text(loc.t("translation_recommended_models"))
                            .font(theme.appFont(size: 11, weight: .semibold))
                            .foregroundColor(ThemeManager.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                            .padding(.bottom, 2)

                        ForEach(presets) { preset in
                            modelPickerRow(id: preset.id, title: preset.label)
                        }
                    }

                    if !fetched.isEmpty {
                        Text(loc.t("translation_fetched_models"))
                            .font(theme.appFont(size: 11, weight: .semibold))
                            .foregroundColor(ThemeManager.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)

                        ForEach(fetched, id: \.self) { modelId in
                            modelPickerRow(id: modelId, title: modelId)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 280, height: 260)
    }

    private func modelPickerRow(id: String, title: String) -> some View {
        Button {
            translation.modelName = id
            showModelPicker = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(ThemeManager.accent)
                    .opacity(translation.modelName == id ? 1 : 0)
                Text(title)
                    .font(theme.appFont(size: 12))
                    .foregroundColor(ThemeManager.primaryText)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Accounts: tap one to switch to it, or add another
    private var updatesSection: some View {
        @Bindable var updates = updates
        return VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("settings_updates"))
                .font(theme.appFont(size: 13, weight: .semibold))
                .foregroundColor(ThemeManager.secondaryText)

            Toggle(loc.t("auto_check_updates"), isOn: $updates.checksAutomatically.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                .toggleStyle(GlassCapsuleToggleStyle())
                .foregroundColor(ThemeManager.primaryText)

            // Installing on its own needs the checks that find the update
            Toggle(loc.t("auto_install_updates"), isOn: $updates.installsAutomatically)
                .toggleStyle(GlassCapsuleToggleStyle())
                .foregroundColor(ThemeManager.primaryText)
                .disabled(!updates.checksAutomatically)
                .opacity(updates.checksAutomatically ? 1 : 0.5)

            Text(loc.t("auto_install_updates_desc"))
                .font(theme.appFont(size: 12))
                .foregroundColor(ThemeManager.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(loc.t("menu_check_updates")) {
                updates.checkForUpdates()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

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
                .buttonStyle(.target)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.target)
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // The Video Feed switch's name, marked as an experiment: the feed rests on an X endpoint the web client only
    // calls from its video viewer, and its behaviour is still being tuned
    private var videoFeedLabel: some View {
        HStack(spacing: 6) {
            Text(loc.t("show_videos_tab"))
            Text(loc.t("experimental"))
                .font(theme.appFont(size: 10, weight: .semibold))
                .foregroundColor(ThemeManager.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(ThemeManager.accent.opacity(theme.isLight ? 0.12 : 0.18)))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // 0. Accounts
                    accountsSection
            
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

                HStack {
                    Text(loc.t("language"))
                        .font(theme.appFont(size: 13))
                        .foregroundColor(ThemeManager.primaryText)
                    Spacer(minLength: 12)
                    Picker("", selection: $loc.currentLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                
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
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                }
                
                // Language and theme colour as rows, label on the left and the system pop-up on the right, like the
                // switches
                HStack {
                    Text(loc.t("theme_colour"))
                        .font(theme.appFont(size: 13))
                        .foregroundColor(ThemeManager.primaryText)
                    Spacer(minLength: 12)
                    Picker("", selection: $theme.themeColor) {
                        ForEach(AppThemeColor.allCases) { color in
                            Label {
                                Text(loc.t(color.displayNameKey))
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(color.accentColor)
                            }
                            .tag(color)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

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
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                }
                
                if theme.useLiquidGlass {
                    Toggle(loc.t("autoplay_media"), isOn: $theme.autoplayMedia.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                } else {
                    Toggle(loc.t("autoplay_media"), isOn: $theme.autoplayMedia.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                        .toggleStyle(GlassCapsuleToggleStyle())
                        .foregroundColor(ThemeManager.primaryText)
                }
                
                if theme.useLiquidGlass {
                    Toggle(isOn: $theme.showVideosTab.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                        videoFeedLabel
                    }
                    .toggleStyle(GlassCapsuleToggleStyle())
                    .foregroundColor(ThemeManager.primaryText)
                } else {
                    Toggle(isOn: $theme.showVideosTab.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                        videoFeedLabel
                    }
                    .toggleStyle(GlassCapsuleToggleStyle())
                    .foregroundColor(ThemeManager.primaryText)
                }
            }
            .padding(14)
            .background(cardBackground)
            
            translationSection

            // Updates, in a build that can verify them
            if updates.isAvailable {
                updatesSection
            }

            // 5. Data & Account Management
            VStack(alignment: .leading, spacing: 12) {
                cacheCleanupRow
                
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.target)
                    
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.target)
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
        .padding(.top, Self.headerHeight + 4)
        .padding(.bottom, 16)
        }

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
            .frame(height: Self.headerHeight)
            // Match the notifications pane so settings scroll beneath the same fading surface.
            .background(
                LinearGradient(colors: [ThemeManager.background, ThemeManager.background.opacity(0.85), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.bottom, -12)
                    .allowsHitTesting(false)
            )
        }
        .frame(width: 480, height: 860)
        .background(ThemeManager.background)
    }
    
    // Clearing the oldest images and videos once the cache passes a chosen size
    @ViewBuilder
    private var cacheCleanupRow: some View {
        @Bindable var cleanup = cacheCleanup
        VStack(alignment: .leading, spacing: 6) {
            if theme.useLiquidGlass {
                Toggle(loc.t("auto_clean_cache"), isOn: $cleanup.isOn.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                    .toggleStyle(GlassCapsuleToggleStyle())
                    .foregroundColor(ThemeManager.primaryText)
            } else {
                Toggle(loc.t("auto_clean_cache"), isOn: $cleanup.isOn.animation(.spring(response: 0.35, dampingFraction: 0.8)))
                    .toggleStyle(GlassCapsuleToggleStyle())
                    .foregroundColor(ThemeManager.primaryText)
            }
            
            if cleanup.isOn {
                HStack(alignment: .firstTextBaseline) {
                    Text(loc.t("cache_limit"))
                        .font(theme.appFont(size: 12, weight: .medium))
                        .foregroundColor(ThemeManager.secondaryText)
                    Spacer()
                    Text(cacheLimitTitle(cleanup.stop))
                        .font(theme.appFont(size: 12, weight: .medium))
                        .foregroundColor(ThemeManager.primaryText)
                        .monospacedDigit()
                }
                .padding(.top, 4)
                
                // The system slider of iOS and iPadOS 26: a smaller and a larger drive at the two ends, as Settings
                // pairs a light and a heavy symbol around its own sliders
                HStack(spacing: 10) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 14))
                        .foregroundColor(ThemeManager.secondaryText)
                        .accessibilityHidden(true)
                    StopSlider(
                        stop: $cleanup.stop,
                        stops: CacheCleanup.followsFreeSpace + 1,
                        onRelease: { MediaCacheManager.shared.pruneCache() }
                    )
                    .accessibilityLabel(loc.t("cache_limit"))
                    .accessibilityValue(cacheLimitTitle(cleanup.stop))
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 19))
                        .foregroundColor(ThemeManager.secondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
    }
    
    private func cacheLimitTitle(_ stop: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: CacheCleanup.bytes(atStop: stop), countStyle: .file)
        guard stop == CacheCleanup.followsFreeSpace else { return size }
        return loc.format("cache_limit_auto", ["size": size])
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

// The system slider, which takes on Liquid Glass while dragged, as the HIG has sliders do. It moves freely and settles
// on the nearest stop when let go, ticking the trackpad each time it passes one; the value shown follows it live.
struct StopSlider: View {
    @Binding var stop: Int
    let stops: Int
    // Called once the thumb is let go, or after a step from the keyboard
    let onRelease: () -> Void

    @State private var dragValue: Double?

    var body: some View {
        Slider(
            value: Binding(
                get: { dragValue ?? Double(stop) },
                set: { value in
                    let nearest = Int(value.rounded())
                    // An arrow key moves it outside a drag: go straight to the next stop in that direction
                    if NSApp.currentEvent?.type == .keyDown {
                        let step = value > Double(stop) ? 1 : (value < Double(stop) ? -1 : 0)
                        let next = min(max(stop + step, 0), stops - 1)
                        dragValue = nil
                        if next != stop { stop = next; onRelease() }
                        return
                    }
                    dragValue = value
                    if nearest != stop {
                        stop = nearest
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                }
            ),
            in: 0...Double(max(stops - 1, 1)),
            onEditingChanged: { editing in
                guard !editing else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { dragValue = nil }
                onRelease()
            }
        )
        .labelsHidden()
        .frame(minHeight: 36)
    }
}
