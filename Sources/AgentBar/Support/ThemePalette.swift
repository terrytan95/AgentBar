import SwiftUI

extension AppThemeColor {
    var title: String {
        switch self {
        case .blue: "Blue"
        case .green: "Green"
        case .purple: "Purple"
        case .orange: "Orange"
        case .graphite: "Graphite"
        }
    }

    var primary: Color {
        switch self {
        case .blue: Color(red: 0.05, green: 0.42, blue: 0.95)
        case .green: Color(red: 0.10, green: 0.63, blue: 0.25)
        case .purple: Color(red: 0.47, green: 0.30, blue: 0.92)
        case .orange: Color(red: 0.88, green: 0.38, blue: 0.12)
        case .graphite: Color(red: 0.36, green: 0.37, blue: 0.40)
        }
    }

    var secondary: Color {
        switch self {
        case .blue: Color(red: 0.22, green: 0.66, blue: 0.92)
        case .green: Color(red: 0.39, green: 0.73, blue: 0.36)
        case .purple: Color(red: 0.67, green: 0.46, blue: 0.88)
        case .orange: Color(red: 0.93, green: 0.58, blue: 0.22)
        case .graphite: Color(red: 0.56, green: 0.57, blue: 0.61)
        }
    }

    var tertiary: Color {
        switch self {
        case .blue: Color(red: 0.45, green: 0.53, blue: 0.64)
        case .green: Color(red: 0.45, green: 0.56, blue: 0.47)
        case .purple: Color(red: 0.52, green: 0.48, blue: 0.62)
        case .orange: Color(red: 0.62, green: 0.50, blue: 0.42)
        case .graphite: Color(red: 0.42, green: 0.43, blue: 0.46)
        }
    }

    func quotaColor(remaining: Double?) -> Color {
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
