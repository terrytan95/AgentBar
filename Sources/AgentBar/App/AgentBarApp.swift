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
        MenuBarExtra {
            PopoverRootView(store: store)
                .frame(width: 430, height: 640)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: AppLogo.templateImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(store.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("AgentBar Statistics", id: "statistics") {
            StatisticsView(store: store)
                .frame(minWidth: 860, minHeight: 620)
        }

        Settings {
            SettingsView(store: store)
        }
        .commandsRemoved()
    }
}

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

        if CommandLine.arguments.contains("--smoke-ui") {
            Task { @MainActor in
                SmokeVerificationWindowController.shared.show()
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSLog("AgentBar showing launch status window")
            LaunchStatusWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async {
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
