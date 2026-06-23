import Foundation

struct PopoverActionRecommendation: Equatable {
    enum Action: Equatable {
        case switchAccount(String)
        case refresh
        case waitForReset
        case none
    }

    var severity: InsightSeverity
    var title: String
    var detail: String
    var actionTitle: String?
    var action: Action

    static func make(
        pressure: QuotaPressureInsight,
        dataSourceHealth: DataSourceHealthSummary,
        language: AppLanguage
    ) -> PopoverActionRecommendation {
        if pressure.activeAccount == nil {
            return PopoverActionRecommendation(
                severity: .warning,
                title: localized("popover_action_refresh_title", language),
                detail: dataSourceHealth.issueCount > 0
                    ? localized("popover_action_refresh_detail", language)
                    : localized("popover_action_no_account_detail", language),
                actionTitle: L.text("refresh", language),
                action: .refresh
            )
        }

        if pressure.severity == .critical || pressure.shouldTriggerRotation {
            if let recommended = pressure.recommendedAccount {
                return PopoverActionRecommendation(
                    severity: .critical,
                    title: localized("popover_action_switch_title", language),
                    detail: switchDetail(active: pressure.activeAccount, recommended: recommended, language: language),
                    actionTitle: actionTitle(prefixKey: "popover_action_use", account: recommended, language: language),
                    action: .switchAccount(recommended.id)
                )
            }

            return PopoverActionRecommendation(
                severity: .critical,
                title: localized("popover_action_wait_title", language),
                detail: waitDetail(active: pressure.activeAccount, language: language),
                actionTitle: nil,
                action: .waitForReset
            )
        }

        if pressure.severity == .warning {
            if let recommended = pressure.recommendedAccount {
                return PopoverActionRecommendation(
                    severity: .warning,
                    title: localized("popover_action_watch_title", language),
                    detail: switchDetail(active: pressure.activeAccount, recommended: recommended, language: language),
                    actionTitle: actionTitle(prefixKey: "popover_action_use", account: recommended, language: language),
                    action: .switchAccount(recommended.id)
                )
            }

            return PopoverActionRecommendation(
                severity: .warning,
                title: localized("popover_action_watch_title", language),
                detail: waitDetail(active: pressure.activeAccount, language: language),
                actionTitle: nil,
                action: .none
            )
        }

        return PopoverActionRecommendation(
            severity: .ok,
            title: localized("popover_action_ready_title", language),
            detail: readyDetail(active: pressure.activeAccount, dataSourceHealth: dataSourceHealth, language: language),
            actionTitle: nil,
            action: .none
        )
    }

    private static func switchDetail(active: UsageAccount?, recommended: UsageAccount, language: AppLanguage) -> String {
        switch language {
        case .english:
            let activeName = active?.displayName ?? "Current account"
            let activeFive = DisplayFormatters.percentString(active?.fiveHourWindow?.remainingPercent)
            let activeWeekly = DisplayFormatters.percentString(active?.weeklyWindow?.remainingPercent)
            let recommendedFive = DisplayFormatters.percentString(recommended.fiveHourWindow?.remainingPercent)
            let recommendedWeekly = DisplayFormatters.percentString(recommended.weeklyWindow?.remainingPercent)
            let resetDetail = resetCreditDetail(for: recommended, language: language)
            return "\(activeName) 5H \(activeFive), WK \(activeWeekly). \(recommended.displayName) 5H \(recommendedFive), WK \(recommendedWeekly)."
                + resetDetail
        case .chinese:
            let activeName = active?.displayName ?? "当前账号"
            let activeFive = DisplayFormatters.percentString(active?.fiveHourWindow?.remainingPercent)
            let activeWeekly = DisplayFormatters.percentString(active?.weeklyWindow?.remainingPercent)
            let recommendedFive = DisplayFormatters.percentString(recommended.fiveHourWindow?.remainingPercent)
            let recommendedWeekly = DisplayFormatters.percentString(recommended.weeklyWindow?.remainingPercent)
            let resetDetail = resetCreditDetail(for: recommended, language: language)
            return "\(activeName) 5H \(activeFive)，本周 \(activeWeekly)。\(recommended.displayName) 5H \(recommendedFive)，本周 \(recommendedWeekly)。"
                + resetDetail
        }
    }

    private static func resetCreditDetail(for account: UsageAccount, language: AppLanguage) -> String {
        guard let resetCredits = account.resetCredits, resetCredits.hasAvailableCredits else { return "" }
        switch language {
        case .english:
            return " \(resetCredits.summaryLine(language: language))."
        case .chinese:
            return " \(resetCredits.summaryLine(language: language))。"
        }
    }

    private static func waitDetail(active: UsageAccount?, language: AppLanguage) -> String {
        let resetLine = active?.fiveHourWindow?.resetLine(language: language)
            ?? active?.weeklyWindow?.resetLine(language: language)
            ?? L.text("reset_time_unknown", language)
        switch language {
        case .english:
            return "No better account is available. \(resetLine)"
        case .chinese:
            return "暂无更合适账号。\(resetLine)"
        }
    }

    private static func readyDetail(
        active: UsageAccount?,
        dataSourceHealth: DataSourceHealthSummary,
        language: AppLanguage
    ) -> String {
        let accountName = active?.displayName ?? L.text("current_account", language)
        switch language {
        case .english:
            return "\(accountName) is ready. \(dataSourceHealth.liveCount) live source(s)."
        case .chinese:
            return "\(accountName) 可用。\(dataSourceHealth.liveCount) 个实时数据源。"
        }
    }

    private static func actionTitle(prefixKey: String, account: UsageAccount, language: AppLanguage) -> String {
        "\(localized(prefixKey, language)) \(account.displayName)"
    }

    private static func localized(_ key: String, _ language: AppLanguage) -> String {
        switch (key, language) {
        case ("popover_action_refresh_title", .english): "Refresh usage data"
        case ("popover_action_refresh_title", .chinese): "刷新用量数据"
        case ("popover_action_refresh_detail", .english): "Account data is incomplete or needs authorization."
        case ("popover_action_refresh_detail", .chinese): "账号数据不完整，或需要重新授权。"
        case ("popover_action_no_account_detail", .english): "No active account is loaded yet."
        case ("popover_action_no_account_detail", .chinese): "尚未载入当前账号。"
        case ("popover_action_switch_title", .english): "Switch recommended"
        case ("popover_action_switch_title", .chinese): "建议切换账号"
        case ("popover_action_wait_title", .english): "Wait for reset"
        case ("popover_action_wait_title", .chinese): "等待额度重置"
        case ("popover_action_watch_title", .english): "Watch current quota"
        case ("popover_action_watch_title", .chinese): "关注当前额度"
        case ("popover_action_ready_title", .english): "Ready"
        case ("popover_action_ready_title", .chinese): "状态良好"
        case ("popover_action_use", .english): "Use"
        case ("popover_action_use", .chinese): "使用"
        default: key
        }
    }
}
