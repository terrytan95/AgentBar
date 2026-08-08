import SwiftUI

enum AgentBarPalette {
    static let primary = Color(red: 0.33, green: 0.50, blue: 0.66)
    static let secondary = Color(red: 0.39, green: 0.57, blue: 0.66)
    static let tertiary = Color(red: 0.26, green: 0.43, blue: 0.59)

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
