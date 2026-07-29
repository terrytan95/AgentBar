import Combine
import SwiftUI

@main
struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var store: UsageStore

    init() {
        let settings = SettingsStore.shared
        let store = UsageStore(
            settings: settings,
            codexUsagePreviewReader: {
                CodexUsageReader(sessionFileLimit: 5, prunesSessionCache: false).read()
            }
        )
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        appDelegate.configure(settings: settings, store: store)
    }

    var body: some Scene {
        WindowGroup("AgentBar", id: "statistics") {
            StatisticsView(store: store)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .defaultSize(width: 1480, height: 940)
        .commandsRemoved()
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit AgentBar") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings = SettingsStore.shared
    private var store: UsageStore?
    private var appearanceCancellable: AnyCancellable?

    func configure(settings: SettingsStore, store: UsageStore) {
        self.settings = settings
        self.store = store
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        appearanceCancellable = settings.$useDarkAppearance
            .removeDuplicates()
            .sink { useDarkAppearance in
                NSApp.appearance = useDarkAppearance ? NSAppearance(named: .darkAqua) : nil
            }

        if let reportURL = smokeReportURL() {
            Task { @MainActor in
                SmokeReporter.writeReport(to: reportURL)
                NSApp.terminate(nil)
            }
            return
        }

        let store = store ?? UsageStore(
            settings: settings,
            codexUsagePreviewReader: {
                CodexUsageReader(sessionFileLimit: 5, prunesSessionCache: false).read()
            }
        )
        self.store = store
        store.start()
        StatusItemController.shared.show(settings: settings, store: store)
        CodexSidebarQuotaOverlayController.shared.start(settings: settings, store: store)
        QuotaWidgetHotKeyController.shared.start(settings: settings)
        AppUpdateStore.shared.startAutomaticChecks()

        NSLog("AgentBar launched with menu bar status item")
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
        QuotaWidgetHotKeyController.shared.stop()
        CodexSidebarQuotaOverlayController.shared.stop()
    }

    private func smokeReportURL() -> URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--smoke-report"),
              CommandLine.arguments.indices.contains(index + 1)
        else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
}
