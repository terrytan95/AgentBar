import Foundation

struct CodexUsageSource: Sendable {
    var codexUsageSynchronizer: @Sendable () -> CodexUsageSyncResult
    var codexDetailedResetCreditsSynchronizer: @Sendable () -> CodexUsageSyncResult
    var codexUsageReader: @Sendable () -> UsageSnapshot

    func read(detailedResetCreditsEnabled: Bool) -> UsageSnapshot {
        let syncCodexUsage = detailedResetCreditsEnabled ? codexDetailedResetCreditsSynchronizer : codexUsageSynchronizer
        let syncResult = syncCodexUsage()
        var snapshot = codexUsageReader()
        if let note = syncResult.note {
            snapshot.securityNotes.append(note)
        }
        return snapshot
    }
}
