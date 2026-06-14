import AppKit
import SwiftUI

struct LaunchStatusView: View {
    @StateObject private var store = UsageStore()

    var body: some View {
        StatisticsView(store: store)
    }
}

enum LaunchStatusAccountList {
    static func accountsToDisplay(from accounts: [UsageAccount]) -> [UsageAccount] {
        accounts
    }
}

@MainActor
final class LaunchStatusWindowController {
    static let shared = LaunchStatusWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
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
        window.contentView = NSHostingView(rootView: LaunchStatusView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
