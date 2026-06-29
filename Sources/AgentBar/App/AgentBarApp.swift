import SwiftUI

@main
struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var store: UsageStore

    init() {
        let settings = SettingsStore.shared
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

        let snapshot = CodexUsageReader().read()
        let payload: Any
        if let index = arguments.firstIndex(of: "--usage-mcp"),
           arguments.indices.contains(index + 1) {
            payload = usageMCPPayload(tool: arguments[index + 1], points: snapshot.points, arguments: arguments)
        } else {
            payload = usageSummaryPayload(points: snapshot.points)
        }
        printJSON(payload)
        return true
    }

    private func usageMCPPayload(tool: String, points: [UsagePoint], arguments: [String]) -> Any {
        switch tool {
        case "usage_summary":
            return usageSummaryPayload(points: points)
        case "session_usage":
            return usageSessionPayload(points: points, sessionID: value(after: "--session-id", in: arguments))
        case "expensive_calls":
            return usageSessionPayload(points: points, limit: 25)
                .sorted { ($0["total_tokens"] as? Int ?? 0) > ($1["total_tokens"] as? Int ?? 0) }
        default:
            return [
                "error": "Unknown usage MCP tool.",
                "tools": ["usage_summary", "session_usage", "expensive_calls"]
            ]
        }
    }

    private func usageSummaryPayload(points: [UsagePoint], limit: Int = 20) -> [String: Any] {
        let costs = points.compactMap(\.estimatedCostUSD)
        let totals = points.reduce(TokenTotals.zero) { $0 + $1.tokens }
        let threads = Dictionary(grouping: points) { point in
            point.sessionTitle ?? point.sessionID ?? "Unknown"
        }
        .map { thread, points in
            let cost = points.compactMap(\.estimatedCostUSD).reduce(Decimal(0), +)
            return [
                "thread": thread,
                "calls": points.count,
                "total_tokens": points.reduce(0) { $0 + $1.tokens.total },
                "estimated_cost_usd": NSDecimalNumber(decimal: cost).doubleValue
            ] as [String: Any]
        }
        .sorted { ($0["total_tokens"] as? Int ?? 0) > ($1["total_tokens"] as? Int ?? 0) }
        .prefix(max(1, min(limit, 100)))

        return [
            "totals": [
                "calls": points.count,
                "total_tokens": totals.total,
                "cached_input_tokens": totals.cachedInput,
                "uncached_input_tokens": max(0, totals.input - totals.cachedInput),
                "output_tokens": totals.output,
                "reasoning_output_tokens": totals.reasoningOutput,
                "estimated_cost_usd": NSDecimalNumber(decimal: costs.reduce(Decimal(0), +)).doubleValue
            ],
            "threads": Array(threads)
        ]
    }

    private func usageSessionPayload(points: [UsagePoint], sessionID: String? = nil, limit: Int = 100) -> [[String: Any]] {
        let normalizedLimit = max(1, min(limit, 500))
        return points
            .filter { sessionID?.isEmpty != false || $0.sessionID == sessionID }
            .sorted { $0.date > $1.date }
            .prefix(normalizedLimit)
            .map(usageEventRow)
    }

    private func usageEventRow(_ point: UsagePoint) -> [String: Any] {
        [
            "record_id": point.callID,
            "session_id": point.sessionID as Any? ?? NSNull(),
            "thread_name": point.sessionTitle as Any? ?? NSNull(),
            "event_timestamp": iso8601String(from: point.date),
            "source_file": point.sourceFile as Any? ?? NSNull(),
            "source_line": point.sourceLine as Any? ?? NSNull(),
            "cwd": point.cwd as Any? ?? NSNull(),
            "project_name": point.projectName as Any? ?? NSNull(),
            "model": point.model,
            "effort": point.reasoningEffort as Any? ?? NSNull(),
            "initiator": point.initiator as Any? ?? NSNull(),
            "input_tokens": point.tokens.input,
            "cached_input_tokens": point.tokens.cachedInput,
            "uncached_input_tokens": point.uncachedInputTokens,
            "output_tokens": point.tokens.output,
            "reasoning_output_tokens": point.tokens.reasoningOutput,
            "total_tokens": point.tokens.total,
            "estimated_cost_usd": point.estimatedCostUSD.map { NSDecimalNumber(decimal: $0).doubleValue } as Any? ?? NSNull(),
            "model_context_window": point.modelContextWindow as Any? ?? NSNull()
        ]
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
