//
//  ThemeManager.swift
//  MaX - Headless Data-driven Client
//

import SwiftUI
import AppKit

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
            return [
                NSColor(hex: "#ffffff"),
                NSColor(hex: "#e2e8f0"),
                NSColor(hex: "#94a3b8")
            ]
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
        case .gray: return Color(red: 0.89, green: 0.91, blue: 0.94)
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
    
    @Published var fontType: AppFontType {
        didSet {
            UserDefaults.standard.set(fontType.rawValue, forKey: "MaX_FontType")
        }
    }
    
    @Published var enableShimmer: Bool {
        didSet {
            UserDefaults.standard.set(enableShimmer, forKey: "MaX_EnableShimmer")
        }
    }
    
    @Published var useLiquidGlass: Bool {
        didSet {
            UserDefaults.standard.set(useLiquidGlass, forKey: "MaX_UseLiquidGlass")
        }
    }
    
    @Published var useLiquidGlassTint: Bool {
        didSet {
            UserDefaults.standard.set(useLiquidGlassTint, forKey: "MaX_UseLiquidGlassTint")
        }
    }
    
    @Published var themeColor: AppThemeColor {
        didSet {
            UserDefaults.standard.set(themeColor.rawValue, forKey: "MaX_ThemeColor")
        }
    }
    
    var refreshColor: AppThemeColor {
        get { themeColor }
        set { themeColor = newValue }
    }
    
    private init() {
        if let savedFont = UserDefaults.standard.string(forKey: "MaX_FontType"),
           let ft = AppFontType(rawValue: savedFont) {
            self.fontType = ft
        } else {
            self.fontType = .system
        }
        
        if UserDefaults.standard.object(forKey: "MaX_EnableShimmer") != nil {
            self.enableShimmer = UserDefaults.standard.bool(forKey: "MaX_EnableShimmer")
        } else {
            self.enableShimmer = true
        }
        
        if UserDefaults.standard.object(forKey: "MaX_UseLiquidGlass") != nil {
            self.useLiquidGlass = UserDefaults.standard.bool(forKey: "MaX_UseLiquidGlass")
        } else {
            self.useLiquidGlass = false // Defaults to Liquid Glass Disabled mode as requested
        }
        
        if UserDefaults.standard.object(forKey: "MaX_UseLiquidGlassTint") != nil {
            self.useLiquidGlassTint = UserDefaults.standard.bool(forKey: "MaX_UseLiquidGlassTint")
        } else {
            self.useLiquidGlassTint = true // Defaults to Tint enabled when Liquid Glass is on
        }
        
        if let savedColor = UserDefaults.standard.string(forKey: "MaX_ThemeColor") ?? UserDefaults.standard.string(forKey: "MaX_RefreshAnimationColor"),
           let tc = AppThemeColor(rawValue: savedColor) {
            self.themeColor = tc
        } else {
            self.themeColor = .blue
        }
    }
    
    // OLED Dark Theme Colors
    static let background = Color.black
    static let cardBackground = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let border = Color(white: 0.14)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.58)
    static let tertiaryText = Color(white: 0.38)
    
    // Dynamic Accent Color matching current Theme Colour
    static var accent: Color {
        shared.themeColor.accentColor
    }
    static let retweetGreen = Color(red: 0.0, green: 0.73, blue: 0.44)
    static let heartPink = Color(red: 0.95, green: 0.15, blue: 0.45)
    
    // Dynamic Font Provider
    func tweetFont(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        switch fontType {
        case .system:
            return .system(size: size, weight: weight)
        case .mincho:
            return .custom("Hiragino Mincho ProN", size: size + 0.5)
        }
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
