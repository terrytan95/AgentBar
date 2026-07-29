import Foundation

@MainActor
enum DashboardNavigation {
    static let tabRequestNotification = Notification.Name("AgentBarDashboardTabRequest")
    static let efficiencyCoachRequestNotification = Notification.Name("AgentBarEfficiencyCoachRequest")
    private static var pendingTab: DashboardTopTab?
    private static var pendingEfficiencyCoach = false

    static func request(_ tab: DashboardTopTab) {
        pendingTab = tab
        NotificationCenter.default.post(
            name: tabRequestNotification,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }

    static func consumePendingTab() -> DashboardTopTab? {
        defer { pendingTab = nil }
        return pendingTab
    }

    static func requestEfficiencyCoach() {
        pendingEfficiencyCoach = true
        NotificationCenter.default.post(name: efficiencyCoachRequestNotification, object: nil)
    }

    static func consumePendingEfficiencyCoach() -> Bool {
        defer { pendingEfficiencyCoach = false }
        return pendingEfficiencyCoach
    }
}
