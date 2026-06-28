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

        if handleUsageCommandLine() {
            NSApp.terminate(nil)
            return
        }

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

    private func handleUsageCommandLine() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains("--usage-summary") || arguments.contains("--usage-mcp") else {
            return false
        }

        let store = CodexUsageIndexStore.defaultStore()
        do {
            _ = CodexUsageReader().read()
            let payload: Any
            if let index = arguments.firstIndex(of: "--usage-mcp"),
               arguments.indices.contains(index + 1) {
                payload = try usageMCPPayload(tool: arguments[index + 1], store: store, arguments: arguments)
            } else {
                payload = try store.summaryPayload()
            }
            printJSON(payload)
        } catch {
            printJSON(["error": error.localizedDescription])
        }
        return true
    }

    private func usageMCPPayload(tool: String, store: CodexUsageIndexStore, arguments: [String]) throws -> Any {
        switch tool {
        case "usage_summary":
            return try store.summaryPayload()
        case "session_usage":
            return try store.sessionPayload(sessionID: value(after: "--session-id", in: arguments))
        case "expensive_calls":
            return try store.sessionPayload(limit: 25)
                .sorted { lhs, rhs in
                    (lhs["total_tokens"] as? Int ?? 0) > (rhs["total_tokens"] as? Int ?? 0)
                }
        default:
            return [
                "error": "Unknown usage MCP tool.",
                "tools": ["usage_summary", "session_usage", "expensive_calls"]
            ]
        }
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private func printJSON(_ payload: Any) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            print("{}")
            return
        }
        print(text)
    }
}
