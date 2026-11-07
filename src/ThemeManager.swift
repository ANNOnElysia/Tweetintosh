//
//  ThemeManager.swift
//  Tweetintosh - Headless Data-driven Client
//

import SwiftUI
import AppKit

enum AppThemeAppearance: String, CaseIterable, Identifiable, Codable {
    case dark = "dark"
    case light = "light"
    case system = "system"
    
    var id: String { rawValue }
    
    var displayNameKey: String {
        switch self {
        case .dark: return "theme_dark"
        case .light: return "theme_light"
        case .system: return "theme_system"
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let val = try container.decode(String.self)
        if val == "riceWhite" {
            self = .light
        } else if let app = AppThemeAppearance(rawValue: val) {
            self = app
        } else {
            self = .system
        }
    }
    
    init?(savedValue: String) {
        if savedValue == "riceWhite" {
            self = .light
        } else {
            self.init(rawValue: savedValue)
        }
    }
}

enum AppThemeTone: String, CaseIterable, Identifiable, Codable {
    case mild = "mild"
    case minimalism = "minimalism"
    
    var id: String { rawValue }
    
    var displayNameKey: String {
        switch self {
        case .mild: return "theme_tone_mild"
        case .minimalism: return "theme_tone_minimalism"
        }
    }
}

enum AppFontType: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case mincho = "mincho"
    
    var id: String { rawValue }
}

enum AppThemeColor: String, CaseIterable, Identifiable, Codable {
    case blue = "blue"
    case pink = "pink"
    case green = "green"
    case gray = "gray"
    case orangeRed = "orangeRed"
    
    var id: String { rawValue }
    
    var displayNameKey: String {
        switch self {
        case .blue: return "color_blue"
        case .pink: return "color_pink"
        case .green: return "color_green"
        case .gray: return "color_gray"
        case .orangeRed: return "color_orange_red"
        }
    }
    
    var gradientColors: [NSColor] {
        switch self {
        case .blue:
            return [
                NSColor(hex: "#00c6ff"),
                NSColor(hex: "#0072ff"),
                NSColor(hex: "#7b2ff7")
            ]
        case .pink:
            return [
                NSColor(hex: "#fb8282"),
                NSColor(hex: "#fb7caa"),
                NSColor(hex: "#fa76d1")
            ]
        case .green:
            return [
                NSColor(hex: "#00f2fe"),
                NSColor(hex: "#4facfe"),
                NSColor(hex: "#00f5a0")
            ]
        case .gray:
            // Near-white on a dark background and slate on a light one: the same shades are invisible on the other
            return ThemeManager.shared.isLight
                ? [NSColor(hex: "#374151"), NSColor(hex: "#4b5563"), NSColor(hex: "#6b7280")]
                : [NSColor(hex: "#ffffff"), NSColor(hex: "#e2e8f0"), NSColor(hex: "#94a3b8")]
        case .orangeRed:
            return [
                NSColor(hex: "#ff9a44"),
                NSColor(hex: "#fc6076"),
                NSColor(hex: "#ff0844")
            ]
        }
    }
    
    var accentColor: Color {
        switch self {
        case .blue: return Color(red: 0.11, green: 0.61, blue: 0.94)
        case .pink: return Color(red: 0.98, green: 0.48, blue: 0.67)
        case .green: return Color(red: 0.0, green: 0.96, blue: 0.63)
        // Near-white on the dark background (it needs to stand out on black) and a dark slate on the light one,
        // where near-white vanished into the cream
        case .gray: return ThemeManager.shared.isLight ? Color(hex: "#4B5563") : Color(red: 0.89, green: 0.91, blue: 0.94)
        case .orangeRed: return Color(red: 1.0, green: 0.60, blue: 0.27)
        }
    }
}

typealias RefreshAnimationColor = AppThemeColor

extension NSColor {
    convenience init(hex: String) {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

extension Color {
    init(hex: String) {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var appearance: AppThemeAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "Tweetintosh_Appearance")
            applyAppearance()
        }
    }
    
    @Published var themeTone: AppThemeTone {
        didSet {
            UserDefaults.standard.set(themeTone.rawValue, forKey: "Tweetintosh_ThemeTone")
            applyAppearance()
        }
    }
    
    var isMild: Bool {
        themeTone == .mild
    }
    
    @Published var fontType: AppFontType {
        didSet {
            UserDefaults.standard.set(fontType.rawValue, forKey: "Tweetintosh_FontType")
        }
    }
    
    @Published var useLiquidGlass: Bool {
        didSet {
            UserDefaults.standard.set(useLiquidGlass, forKey: "Tweetintosh_UseLiquidGlass")
        }
    }
    
    @Published var useLiquidGlassTint: Bool {
        didSet {
            UserDefaults.standard.set(useLiquidGlassTint, forKey: "Tweetintosh_UseLiquidGlassTint")
        }
    }
    
    @Published var themeColor: AppThemeColor {
        didSet {
            UserDefaults.standard.set(themeColor.rawValue, forKey: "Tweetintosh_ThemeColor")
        }
    }
    
    @Published var showPromotedPosts: Bool {
        didSet {
            UserDefaults.standard.set(showPromotedPosts, forKey: "Tweetintosh_ShowPromotedPosts")
            NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_PromotedPostsSettingDidChange"), object: nil)
        }
    }
    
    @Published var autoplayMedia: Bool {
        didSet {
            UserDefaults.standard.set(autoplayMedia, forKey: "Tweetintosh_AutoplayMedia")
        }
    }
    
    var refreshColor: AppThemeColor {
        get { themeColor }
        set { themeColor = newValue }
    }
    
    var isLight: Bool {
        switch appearance {
        case .dark:
            return false
        case .light:
            return true
        case .system:
            return NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        }
    }
    
    // macOS switching between light and dark by itself (the "System" choice): everything that reads isLight must
    // redraw, and the windows' own background colours must be set again
    private var systemAppearanceObservation: NSKeyValueObservation?
    
    private func watchSystemAppearance() {
        DispatchQueue.main.async {
            guard self.systemAppearanceObservation == nil, let app = NSApp else { return }
            self.systemAppearanceObservation = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self = self, self.appearance == .system else { return }
                    self.objectWillChange.send()
                    NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_AppearanceDidChange"), object: nil)
                }
            }
        }
    }
    
    func applyAppearance() {
        // At once when possible, so the first window already draws in the right appearance. The announcement still waits a
        // turn: this also runs while ThemeManager.shared is being created, and listeners read it back.
        if Thread.isMainThread { setAppAppearance() }
        DispatchQueue.main.async {
            self.setAppAppearance()
            self.objectWillChange.send()
            NotificationCenter.default.post(name: NSNotification.Name("Tweetintosh_AppearanceDidChange"), object: nil)
        }
    }

    private func setAppAppearance() {
        switch appearance {
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApp?.appearance = NSAppearance(named: .aqua)
        case .system:
            NSApp?.appearance = nil
        }
    }
    
    private init() {
        if let savedApp = UserDefaults.standard.string(forKey: "Tweetintosh_Appearance"),
           let app = AppThemeAppearance(savedValue: savedApp) {
            self.appearance = app
        } else {
            // A new install looks like the rest of the Mac until the reader picks something else
            self.appearance = .system
        }
        
        if let savedTone = UserDefaults.standard.string(forKey: "Tweetintosh_ThemeTone"),
           let tone = AppThemeTone(rawValue: savedTone) {
            self.themeTone = tone
        } else {
            self.themeTone = .mild
        }
        
        if let savedFont = UserDefaults.standard.string(forKey: "Tweetintosh_FontType"),
           let ft = AppFontType(rawValue: savedFont) {
            self.fontType = ft
        } else {
            self.fontType = .system
        }
        
        if UserDefaults.standard.object(forKey: "Tweetintosh_UseLiquidGlass") != nil {
            self.useLiquidGlass = UserDefaults.standard.bool(forKey: "Tweetintosh_UseLiquidGlass")
        } else {
            self.useLiquidGlass = false
        }
        if UserDefaults.standard.object(forKey: "Tweetintosh_UseLiquidGlassTint") != nil {
            self.useLiquidGlassTint = UserDefaults.standard.bool(forKey: "Tweetintosh_UseLiquidGlassTint")
        } else {
            self.useLiquidGlassTint = true
        }
        
        if let savedColor = UserDefaults.standard.string(forKey: "Tweetintosh_ThemeColor") ?? UserDefaults.standard.string(forKey: "Tweetintosh_RefreshAnimationColor"),
           let tc = AppThemeColor(rawValue: savedColor) {
            self.themeColor = tc
        } else {
            self.themeColor = .blue
        }
        
        if UserDefaults.standard.object(forKey: "Tweetintosh_ShowPromotedPosts") != nil {
            self.showPromotedPosts = UserDefaults.standard.bool(forKey: "Tweetintosh_ShowPromotedPosts")
        } else {
            self.showPromotedPosts = false
        }
        
        self.autoplayMedia = UserDefaults.standard.object(forKey: "Tweetintosh_AutoplayMedia") as? Bool ?? true
        
        applyAppearance()
        watchSystemAppearance()
    }
    
    // Dynamic Theme Colors:
    // Mild: Rice White (#F6F4EE) for light, Dim (#15202B) for dark
    // Minimalism: Pure White (#FFFFFF) for light, Pitch Black (#000000) for dark
    static var background: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#F6F4EE") : Color.white
        } else {
            return shared.isMild ? Color(hex: "#15202B") : Color.black
        }
    }
    static var windowBackgroundColor: NSColor {
        if shared.isLight {
            return shared.isMild
                ? NSColor(calibratedRed: 0.965, green: 0.957, blue: 0.933, alpha: 1.0)
                : NSColor.white
        } else {
            return shared.isMild
                ? NSColor(hex: "#15202B")
                : NSColor.black
        }
    }
    static var cardBackground: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#FAF9F5") : Color(hex: "#F8F9FA")
        } else {
            return shared.isMild ? Color(hex: "#1E2732") : Color(red: 0.05, green: 0.05, blue: 0.06)
        }
    }
    static var border: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#E5E1D5") : Color(hex: "#E5E7EB")
        } else {
            return shared.isMild ? Color(hex: "#2F3B47") : Color(white: 0.14)
        }
    }
    static var divider: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#ECE8DC") : Color(hex: "#EEEEF0")
        } else {
            return shared.isMild ? Color(hex: "#273340") : Color.white.opacity(0.08)
        }
    }
    static var primaryText: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#1A1A1C") : Color.black
        } else {
            return shared.isMild ? Color(hex: "#F7F9F9") : Color.white
        }
    }
    static var secondaryText: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#666461") : Color(hex: "#555555")
        } else {
            return shared.isMild ? Color(hex: "#8B98A5") : Color(white: 0.58)
        }
    }
    static var tertiaryText: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#9E9A93") : Color(hex: "#8E8E93")
        } else {
            return shared.isMild ? Color(hex: "#6E7B87") : Color(white: 0.38)
        }
    }
    static var subtleIcon: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#504E4B") : Color(hex: "#48484A")
        } else {
            return shared.isMild ? Color(hex: "#8B98A5") : Color.white.opacity(0.70)
        }
    }
    static var glassPillInactive: Color {
        if shared.isLight {
            return Color.black.opacity(0.05)
        } else {
            return shared.isMild ? Color.white.opacity(0.06) : Color.white.opacity(0.08)
        }
    }
    static var glassBorder: Color {
        if shared.isLight {
            return shared.isMild ? Color(hex: "#DED9CB").opacity(0.8) : Color.black.opacity(0.10)
        } else {
            return shared.isMild ? Color(hex: "#38444D").opacity(0.8) : Color.white.opacity(0.18)
        }
    }
    
    // Dynamic Accent Color matching current Theme Colour
    static var accent: Color {
        shared.themeColor.accentColor
    }
    // The colour for text and icons sitting on a solid accent fill (a button or pill): white, except for the gray
    // theme on the dark background, where the accent is near-white and needs dark text
    static var onAccent: Color {
        (shared.themeColor == .gray && !shared.isLight) ? Color(hex: "#111114") : .white
    }
    static let retweetGreen = Color(red: 0.0, green: 0.73, blue: 0.44)
    static let heartPink = Color(red: 0.95, green: 0.15, blue: 0.45)
    
    // Dynamic Font Provider
    
    /// Resolves the authentic serif font name based on language context:
    /// - Japanese: "Hiragino Mincho ProN" (authentic JIS Mincho & kana)
    /// - Traditional Chinese: "Songti TC" (orthodox Traditional Chinese Ming/Songti)
    /// - Simplified Chinese: "Songti SC" (GB18030 complete coverage with unified baseline)
    /// - English / Korean / other: checks system preferred languages; defaults to "Songti SC" for complete CJK coverage
    var activeSerifFontName: String {
        switch LocalizationManager.shared.currentLanguage {
        case .japanese:
            return "Hiragino Mincho ProN"
        case .traditionalChinese:
            return "Songti TC"
        case .simplifiedChinese:
            return "Songti SC"
        case .english, .korean:
            let preferred = Locale.preferredLanguages.first ?? ""
            if preferred.hasPrefix("ja") {
                return "Hiragino Mincho ProN"
            } else if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-HK") || preferred.hasPrefix("zh-TW") {
                return "Songti TC"
            } else {
                return "Songti SC"
            }
        }
    }
    
    func appFont(size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        switch fontType {
        case .system:
            return .system(size: size, weight: weight)
        case .mincho:
            return .custom(activeSerifFontName, size: size + 0.5).weight(weight)
        }
    }
    
    func tweetFont(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        appFont(size: size, weight: weight)
    }
    
    static func font(size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        ThemeManager.shared.appFont(size: size, weight: weight)
    }
    
    func lineSpacing() -> CGFloat {
        switch fontType {
        case .system:
            return 4.0
        case .mincho:
            return 6.5
        }
    }
}

extension View {
    func appFont(size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        self.font(ThemeManager.shared.appFont(size: size, weight: weight))
    }
}
