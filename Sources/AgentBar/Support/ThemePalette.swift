import SwiftUI

extension AppThemeColor {
    var primary: Color {
        Color(red: 0.05, green: 0.42, blue: 0.95)
    }

    var secondary: Color {
        Color(red: 0.22, green: 0.66, blue: 0.92)
    }

    var tertiary: Color {
        Color(red: 0.45, green: 0.53, blue: 0.64)
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
