import SwiftUI

enum AgentBarColorTheme: String, CaseIterable, Identifiable {
    case classic
    case mistSage
    case hazeBlue
    case dustyRose
    case mutedClay
    case moss
    case smokedLavender
    case stoneTaupe
    case lakeGray

    static let storageKey = "colorTheme"

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.classic, .english): "Classic blue"
        case (.mistSage, .english): "Mist sage"
        case (.hazeBlue, .english): "Haze blue"
        case (.dustyRose, .english): "Dusty rose"
        case (.mutedClay, .english): "Muted clay"
        case (.moss, .english): "Moss"
        case (.smokedLavender, .english): "Smoked lavender"
        case (.stoneTaupe, .english): "Stone taupe"
        case (.lakeGray, .english): "Lake gray"
        case (.classic, .chinese): "经典蓝"
        case (.mistSage, .chinese): "雾松绿"
        case (.hazeBlue, .chinese): "雾霾蓝"
        case (.dustyRose, .chinese): "豆沙红"
        case (.mutedClay, .chinese): "灰粉陶"
        case (.moss, .chinese): "苔藓绿"
        case (.smokedLavender, .chinese): "烟熏紫"
        case (.stoneTaupe, .chinese): "岩灰褐"
        case (.lakeGray, .chinese): "灰湖蓝"
        }
    }

    var color: Color {
        adaptiveColor()
    }

    func color(blendedWith target: NSColor, fraction: CGFloat) -> Color {
        adaptiveColor { $0.blended(withFraction: fraction, of: target) ?? $0 }
    }

    private var colors: (light: NSColor, dark: NSColor) {
        switch self {
        case .classic: (light: NSColor(red: 0.29, green: 0.50, blue: 0.70, alpha: 1), dark: NSColor(red: 0.55, green: 0.72, blue: 0.88, alpha: 1))
        case .mistSage: (light: NSColor(red: 0.35, green: 0.42, blue: 0.39, alpha: 1), dark: NSColor(red: 0.65, green: 0.71, blue: 0.68, alpha: 1))
        case .hazeBlue: (light: NSColor(red: 0.36, green: 0.43, blue: 0.49, alpha: 1), dark: NSColor(red: 0.67, green: 0.72, blue: 0.77, alpha: 1))
        case .dustyRose: (light: NSColor(red: 0.47, green: 0.37, blue: 0.40, alpha: 1), dark: NSColor(red: 0.77, green: 0.68, blue: 0.71, alpha: 1))
        case .mutedClay: (light: NSColor(red: 0.48, green: 0.38, blue: 0.36, alpha: 1), dark: NSColor(red: 0.78, green: 0.69, blue: 0.67, alpha: 1))
        case .moss: (light: NSColor(red: 0.38, green: 0.42, blue: 0.32, alpha: 1), dark: NSColor(red: 0.70, green: 0.73, blue: 0.61, alpha: 1))
        case .smokedLavender: (light: NSColor(red: 0.41, green: 0.38, blue: 0.46, alpha: 1), dark: NSColor(red: 0.72, green: 0.69, blue: 0.76, alpha: 1))
        case .stoneTaupe: (light: NSColor(red: 0.44, green: 0.40, blue: 0.36, alpha: 1), dark: NSColor(red: 0.73, green: 0.69, blue: 0.64, alpha: 1))
        case .lakeGray: (light: NSColor(red: 0.35, green: 0.44, blue: 0.44, alpha: 1), dark: NSColor(red: 0.66, green: 0.74, blue: 0.73, alpha: 1))
        }
    }

    private func adaptiveColor(transform: @escaping (NSColor) -> NSColor = { $0 }) -> Color {
        let colors = colors
        return Color(nsColor: NSColor(name: nil) { appearance in
            transform(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? colors.dark : colors.light)
        })
    }
}

enum AgentBarPalette {
    static var primary: Color { currentTheme.color }
    static var secondary: Color { currentTheme.color(blendedWith: .white, fraction: 0.12) }
    static var tertiary: Color { currentTheme.color(blendedWith: .black, fraction: 0.16) }

    private static var currentTheme: AgentBarColorTheme {
        AgentBarColorTheme(rawValue: UserDefaults.standard.string(forKey: AgentBarColorTheme.storageKey) ?? "") ?? .classic
    }

    static func quotaColor(remaining: Double?) -> Color {
        guard let remaining else { return tertiary }
        if remaining < 15 { return .red }
        if remaining < 35 { return .orange }
        return primary
    }
}

extension AccountSortMode {
    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.quotaPressure, .english): "Resets, then 5H"
        case (.activeFirst, .english): "Current first"
        case (.alphabetical, .english): "Name"
        case (.quotaPressure, .chinese): "先重置，再 5 小时"
        case (.activeFirst, .chinese): "当前账号优先"
        case (.alphabetical, .chinese): "按名称"
        }
    }
}
