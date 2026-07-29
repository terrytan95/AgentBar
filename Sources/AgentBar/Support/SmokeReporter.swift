import Foundation

enum SmokeReporter {
    @MainActor
    static func writeReport(to url: URL) {
        let settings = SettingsStore()
        let codex = CodexUsageReader().read()
        let claude = ClaudeUsageReader.discover(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        let accounts = codex.accounts + claude.accounts
        let points = codex.points + claude.points
        let summary = UsageStatistics.summarize(points: points, range: .all)
        let menuStore = UsageStore(
            settings: settings,
            cursorUsageReader: { await CursorAgentUsageReader().read() }
        )
        menuStore.applyTestData(snapshots: [.codex: codex, .claudeCode: claude], accounts: accounts, points: points)
        let displayedAccounts = menuStore.accounts

        var lines: [String] = []
        lines.append("AgentBar smoke report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Menu bar title: \(menuStore.menuBarTitle)")
        lines.append("Popover account rows: \(displayedAccounts.count)")
        lines.append("Active account: \(displayedAccounts.first(where: \.isActive)?.displayName ?? "N/A")")
        lines.append("Statistics total tokens: \(DisplayFormatters.tokenString(summary.totalTokens))")
        lines.append("Statistics total cost: \(summary.estimatedCostUSD.map { DisplayFormatters.costString($0) } ?? "No cost data")")
        lines.append("Pricing fingerprint: \(summary.pricingFingerprint)")
        lines.append("Settings language: \(settings.language.title)")
        lines.append("Settings refresh interval: \(Int(settings.refreshInterval))s")
        lines.append("Settings launch at login: \(settings.launchAtLogin)")
        lines.append("Settings menu mode: \(settings.menuBarDisplayMode.rawValue)")
        lines.append("Settings dark theme: \(settings.useDarkAppearance)")
        lines.append("Settings account sort: \(settings.accountSortMode.rawValue)")
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
        for account in displayedAccounts {
            let quotaWindows = [
                account.fiveHourWindow.map { "5h \(DisplayFormatters.percentString($0.remainingPercent))" },
                account.weeklyWindow.map { "weekly \(DisplayFormatters.percentString($0.remainingPercent))" }
            ].compactMap { $0 }.joined(separator: " | ")
            let username = account.username ?? "N/A"
            lines.append("- \(account.service.rawValue) | \(account.displayName) | \(username) | active \(account.isActive) | \(quotaWindows) | \(account.status.rawValue)")
        }

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
