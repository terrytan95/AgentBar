import SwiftUI

@main
struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsStore()
    @StateObject private var store: UsageStore

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: UsageStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup("AgentBar", id: "statistics") {
            StatisticsView(store: store)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(settings.useDarkAppearance ? .dark : .light)
                .animation(nil, value: settings.useDarkAppearance)
        }
        .defaultSize(width: 1480, height: 940)
        .commandsRemoved()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        if let reportURL = smokeReportURL() {
            Task { @MainActor in
                SmokeReporter.writeReport(to: reportURL)
                NSApp.terminate(nil)
            }
            return
        }

        StatusItemController.shared.show()
        AppUpdateStore.shared.startAutomaticChecks()

        NSLog("AgentBar launched with menu bar status item")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSLog("AgentBar handling reopen")
            LaunchStatusWindowController.shared.show()
        }
        return true
    }

    private func smokeReportURL() -> URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--smoke-report"),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
}
