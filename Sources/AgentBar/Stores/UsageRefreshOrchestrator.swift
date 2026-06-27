import Foundation

struct UsageRefreshResult: Equatable, Sendable {
    var snapshots: [UsageService: UsageSnapshot]
    var accounts: [UsageAccount]
    var points: [UsagePoint]
}

struct UsageRefreshOrchestrator: Sendable {
    var codexUsageSource: @Sendable (Bool) -> UsageSnapshot
    var claudeUsageReader: @Sendable () -> UsageSnapshot

    func refresh(detailedResetCreditsEnabled: Bool) -> UsageRefreshResult {
        let codex = codexUsageSource(detailedResetCreditsEnabled)
        let claude = claudeUsageReader()

        return UsageRefreshResult(
            snapshots: [.codex: codex, .claudeCode: claude],
            accounts: codex.accounts + claude.accounts,
            points: codex.points + claude.points
        )
    }
}
