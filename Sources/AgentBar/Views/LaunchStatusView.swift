import Foundation

enum DashboardNavigation {
    static let tabRequestNotification = Notification.Name("AgentBarDashboardTabRequest")

    static func request(_ tab: DashboardTopTab) {
        NotificationCenter.default.post(
            name: tabRequestNotification,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }
}
