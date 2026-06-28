import AppKit
import SwiftUI

@MainActor
enum MainWindowPresenter {
    static func showMainWindow(initialTab: DashboardTopTab = .usage) {
        if let window = NSApp.windows.first(where: { $0.title == "AgentBar" && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DashboardNavigation.request(initialTab)
            return
        }
        LaunchStatusWindowController.shared.show(initialTab: initialTab)
    }
}

struct LaunchStatusView: View {
    @StateObject private var store = UsageStore()
    var initialTab: DashboardTopTab = .usage

    var body: some View {
        StatisticsView(store: store, initialTab: initialTab)
            .preferredColorScheme(store.settings.useDarkAppearance ? .dark : .light)
            .animation(nil, value: store.settings.useDarkAppearance)
    }
}

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

@MainActor
final class LaunchStatusWindowController {
    static let shared = LaunchStatusWindowController()

    private var window: NSWindow?

    func show(initialTab: DashboardTopTab = .usage) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            DashboardNavigation.request(initialTab)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentBar"
        window.center()
        window.contentView = NSHostingView(rootView: LaunchStatusView(initialTab: initialTab))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
