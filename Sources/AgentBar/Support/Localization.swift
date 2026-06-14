import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case chinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }
}

enum L {
    static func text(_ key: String, _ language: AppLanguage) -> String {
        switch language {
        case .english:
            english[key] ?? key
        case .chinese:
            chinese[key] ?? english[key] ?? key
        }
    }

    private static let english: [String: String] = [
        "overview": "Overview",
        "statistics": "Statistics",
        "settings": "Settings",
        "refresh": "Refresh",
        "show_hud": "Show HUD",
        "hide_hud": "Hide HUD",
        "five_hour": "5-hour",
        "weekly": "Weekly",
        "remaining": "remaining",
        "tokens": "Tokens",
        "cost": "Cost",
        "service_mix": "Service mix",
        "model_detail": "Model detail",
        "range": "Range",
        "data_sources": "Data sources",
        "security": "Security",
        "refresh_interval": "Refresh interval",
        "login_item": "Open at login",
        "menu_item": "Menu bar item",
        "language": "Language",
        "lowest_remaining": "Lowest remaining",
        "total_tokens": "Total tokens",
        "codex_only": "Codex remaining",
        "custom_range": "Custom range",
        "empty_cost": "Cost requires model pricing or an authorized Admin API source.",
        "claude_unavailable": "Claude Code source unavailable"
    ]

    private static let chinese: [String: String] = [
        "overview": "概览",
        "statistics": "统计",
        "settings": "设置",
        "refresh": "刷新",
        "show_hud": "显示 HUD",
        "hide_hud": "隐藏 HUD",
        "five_hour": "5 小时",
        "weekly": "本周",
        "remaining": "剩余",
        "tokens": "Token",
        "cost": "费用",
        "service_mix": "服务占比",
        "model_detail": "模型明细",
        "range": "范围",
        "data_sources": "数据源",
        "security": "安全",
        "refresh_interval": "刷新间隔",
        "login_item": "开机启动",
        "menu_item": "菜单栏显示",
        "language": "语言",
        "lowest_remaining": "最低剩余额度",
        "total_tokens": "总 Token",
        "codex_only": "Codex 剩余",
        "custom_range": "自定义范围",
        "empty_cost": "费用需要模型价格或授权的 Admin API 数据源。",
        "claude_unavailable": "Claude Code 数据源不可用"
    ]
}
