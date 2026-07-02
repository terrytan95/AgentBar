import Foundation

@MainActor
enum DashboardNavigation {
    static let tabRequestNotification = Notification.Name("AgentBarDashboardTabRequest")
    private static var pendingTab: DashboardTopTab?

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
}
