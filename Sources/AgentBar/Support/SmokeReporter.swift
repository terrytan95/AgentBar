import Foundation

enum SmokeReporter {
    @MainActor
    static func writeReport(to url: URL) {
        let settings = SettingsStore()
        let codex = CodexUsageReader().read()
        let claude = ClaudeUsageReader().read()
        let accounts = codex.accounts + claude.accounts
        let points = codex.points + claude.points
        let summary = UsageStatistics.summarize(points: points, range: .all)
        let lowestRemaining = accounts.compactMap(\.mostConstrainedRemainingPercent).min()

        var lines: [String] = []
        lines.append("AgentBar smoke report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Menu bar title: \(DisplayFormatters.percentString(lowestRemaining))")
        lines.append("Popover account rows: \(accounts.count)")
        lines.append("HUD remaining percent: \(DisplayFormatters.percentString(lowestRemaining))")
        lines.append("Statistics total tokens: \(DisplayFormatters.tokenString(summary.totalTokens))")
        lines.append("Statistics total cost: \(DisplayFormatters.costString(summary.estimatedCostUSD))")
        lines.append("Settings language: \(settings.language.title)")
        lines.append("Settings refresh interval: \(Int(settings.refreshInterval))s")
        lines.append("Settings launch at login: \(settings.launchAtLogin)")
        lines.append("Settings menu mode: \(settings.menuBarDisplayMode.rawValue)")
        lines.append("Codex source status: \(codex.status.rawValue)")
        lines.append("Claude Code source status: \(claude.status.rawValue)")
        lines.append("Codex account count: \(codex.accounts.count)")
        lines.append("Claude Code account count: \(claude.accounts.count)")
        let ranges = UsageRange.allCases.map(\.rawValue).joined(separator: ", ")
        let serviceRows = summary.serviceBreakdown
            .map { "\($0.key.rawValue)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        lines.append("Stats ranges covered: \(ranges)")
        lines.append("Service breakdown: \(serviceRows)")
        lines.append("Model breakdown rows: \(summary.modelBreakdown.count)")
        lines.append("Security notes:")
        for note in (codex.securityNotes + claude.securityNotes) {
            lines.append("- \(note.redactedForCredentialWords)")
        }
        lines.append("Accounts:")
        for account in accounts {
            let fiveHour = DisplayFormatters.percentString(account.fiveHourWindow?.remainingPercent)
            let weekly = DisplayFormatters.percentString(account.weeklyWindow?.remainingPercent)
            let email = account.maskedEmail ?? "N/A"
            lines.append("- \(account.service.rawValue) | \(account.displayName) | \(email) | 5h \(fiveHour) | weekly \(weekly) | \(account.status.rawValue)")
        }

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
