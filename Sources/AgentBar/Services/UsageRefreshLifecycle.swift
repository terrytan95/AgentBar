import Foundation

@MainActor
final class UsageRefreshLifecycle {
    struct Result: Sendable {
        let snapshots: [UsageService: UsageSnapshot]
        let accounts: [UsageAccount]
        let points: [UsagePoint]
        let tasks: [AgentTask]
        let generation: UInt64
    }

    enum Completion: Sendable {
        case result(Result)
        case timedOut
    }

    typealias Receiver = @MainActor @Sendable (Completion) -> Void

    private struct Run {
        let generation: UInt64
        var workTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    private let codexUsageSynchronizer: @Sendable () async -> CodexUsageSyncResult
    private let codexUsageReader: @Sendable () -> UsageSnapshot
    private let claudeUsageReader: @Sendable () -> UsageSnapshot
    private let refreshTimeout: Duration
    private var generation: UInt64 = 0
    private var inFlight: Run?
    private var refreshQueued = false

    init(
        codexUsageSynchronizer: @escaping @Sendable () async -> CodexUsageSyncResult,
        codexUsageReader: @escaping @Sendable () -> UsageSnapshot,
        claudeUsageReader: @escaping @Sendable () -> UsageSnapshot,
        refreshTimeout: Duration = .seconds(60)
    ) {
        self.codexUsageSynchronizer = codexUsageSynchronizer
        self.codexUsageReader = codexUsageReader
        self.claudeUsageReader = claudeUsageReader
        self.refreshTimeout = refreshTimeout
    }

    @discardableResult
    func refresh(
        force: Bool,
        receive: @escaping Receiver
    ) -> Bool {
        guard inFlight == nil else {
            refreshQueued = refreshQueued || force
            return false
        }
        start(receive: receive)
        return true
    }

    func reset() {
        generation &+= 1
        inFlight?.workTask?.cancel()
        inFlight?.timeoutTask?.cancel()
        inFlight = nil
        refreshQueued = false
    }

    private func start(receive: @escaping Receiver) {
        generation &+= 1
        let runGeneration = generation
        let codexUsageSynchronizer = codexUsageSynchronizer
        let codexUsageReader = codexUsageReader
        let claudeUsageReader = claudeUsageReader
        inFlight = Run(generation: runGeneration)

        let workTask = Task.detached(priority: .utility) { [weak self] in
            let syncResult = await codexUsageSynchronizer()
            guard !Task.isCancelled else { return }
            var codex = codexUsageReader()
            guard !Task.isCancelled else { return }
            if let note = syncResult.note {
                codex.securityNotes.append(note)
            }
            let claude = claudeUsageReader()
            guard !Task.isCancelled else { return }
            let result = Result(
                snapshots: [.codex: codex, .claudeCode: claude],
                accounts: codex.accounts + claude.accounts,
                points: codex.points + claude.points,
                tasks: codex.tasks,
                generation: runGeneration
            )
            await self?.finish(.result(result), generation: runGeneration, receive: receive)
        }
        guard inFlight?.generation == runGeneration else {
            workTask.cancel()
            return
        }
        inFlight?.workTask = workTask

        let refreshTimeout = refreshTimeout
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: refreshTimeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finish(.timedOut, generation: runGeneration, receive: receive)
        }
        guard inFlight?.generation == runGeneration else {
            timeoutTask.cancel()
            return
        }
        inFlight?.timeoutTask = timeoutTask
    }

    private func finish(
        _ completion: Completion,
        generation runGeneration: UInt64,
        receive: @escaping Receiver
    ) {
        guard let run = inFlight, run.generation == runGeneration else { return }
        run.workTask?.cancel()
        run.timeoutTask?.cancel()
        inFlight = nil

        let shouldRepeat = refreshQueued
        refreshQueued = false
        if shouldRepeat {
            start(receive: receive)
        } else {
            receive(completion)
        }
    }
}
