import Foundation

@MainActor
final class UsageRefreshLifecycle {
    struct Result: Sendable {
        var snapshots: [UsageService: UsageSnapshot]
        var accounts: [UsageAccount]
        var points: [UsagePoint]
        var tasks: [AgentTask]
    }

    private let codexUsageSource: @Sendable () async -> UsageSnapshot
    private let claudeUsageReader: @Sendable () -> UsageSnapshot
    private var isInFlight = false
    private var refreshQueued = false

    init(
        codexUsageSynchronizer: @escaping @Sendable () async -> CodexUsageSyncResult,
        codexUsageReader: @escaping @Sendable () -> UsageSnapshot,
        claudeUsageReader: @escaping @Sendable () -> UsageSnapshot
    ) {
        codexUsageSource = {
            let syncResult = await codexUsageSynchronizer()
            var snapshot = codexUsageReader()
            if let note = syncResult.note {
                snapshot.securityNotes.append(note)
            }
            return snapshot
        }
        self.claudeUsageReader = claudeUsageReader
    }

    @discardableResult
    func refresh(
        force: Bool,
        receive: @escaping @MainActor @Sendable (Result, Bool) -> Void
    ) -> Bool {
        guard !isInFlight else {
            refreshQueued = refreshQueued || force
            return false
        }
        start(receive: receive)
        return true
    }

    func reset() {
        isInFlight = false
        refreshQueued = false
    }

    private func start(
        receive: @escaping @MainActor @Sendable (Result, Bool) -> Void
    ) {
        isInFlight = true
        let codexUsageSource = codexUsageSource
        let claudeUsageReader = claudeUsageReader
        Task.detached(priority: .utility) { [weak self] in
            let codex = await codexUsageSource()
            let claude = claudeUsageReader()
            let result = Result(
                snapshots: [.codex: codex, .claudeCode: claude],
                accounts: codex.accounts + claude.accounts,
                points: codex.points + claude.points,
                tasks: codex.tasks
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isInFlight = false
                let shouldRepeat = self.refreshQueued
                self.refreshQueued = false
                receive(result, !shouldRepeat)
                if shouldRepeat {
                    self.start(receive: receive)
                }
            }
        }
    }
}
