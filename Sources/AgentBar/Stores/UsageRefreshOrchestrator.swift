import Foundation

struct UsageRefreshResult: Equatable, Sendable {
    var snapshots: [UsageService: UsageSnapshot]
    var accounts: [UsageAccount]
    var points: [UsagePoint]
}

struct UsageRefreshOrchestrator: Sendable {
    var codexUsageSynchronizer: @Sendable () -> CodexUsageSyncResult
    var codexDetailedResetCreditsSynchronizer: @Sendable () -> CodexUsageSyncResult
    var codexUsageReader: @Sendable () -> UsageSnapshot
    var claudeUsageReader: @Sendable () -> UsageSnapshot

    func refresh(detailedResetCreditsEnabled: Bool) -> UsageRefreshResult {
        let syncCodexUsage = detailedResetCreditsEnabled ? codexDetailedResetCreditsSynchronizer : codexUsageSynchronizer
        let syncResult = syncCodexUsage()
        var codex = codexUsageReader()
        if let note = syncResult.note {
            codex.securityNotes.append(note)
        }
        let claude = claudeUsageReader()

        return UsageRefreshResult(
            snapshots: [.codex: codex, .claudeCode: claude],
            accounts: codex.accounts + claude.accounts,
            points: codex.points + claude.points
        )
    }
}
