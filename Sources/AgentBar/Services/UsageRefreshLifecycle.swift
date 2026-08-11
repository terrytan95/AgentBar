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
        case progress(Result)
        case result(Result)
        case timedOut
    }

    typealias Receiver = @MainActor @Sendable (Completion) -> Void

    private struct Run {
        let generation: UInt64
        var workTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    private let codexUsageSynchronizer: @Sendable (Bool) async -> CodexUsageSyncResult
    private let codexUsagePreviewReader: (@Sendable () -> UsageSnapshot)?
    private let codexUsageReader: @Sendable () -> UsageSnapshot
    private let claudeUsageReader: @Sendable () -> UsageSnapshot
    private let xaiUsageReader: @Sendable () async -> UsageSnapshot?
    private let cursorUsageReader: @Sendable () async -> UsageSnapshot?
    private let refreshTimeout: Duration
    private var generation: UInt64 = 0
    private var inFlight: Run?
    private var refreshQueued = false
    private var refreshAllCodexAccountsQueued = false

    init(
        codexUsageSynchronizer: @escaping @Sendable (Bool) async -> CodexUsageSyncResult,
        codexUsagePreviewReader: (@Sendable () -> UsageSnapshot)? = nil,
        codexUsageReader: @escaping @Sendable () -> UsageSnapshot,
        claudeUsageReader: @escaping @Sendable () -> UsageSnapshot,
        xaiUsageReader: @escaping @Sendable () async -> UsageSnapshot? = { nil },
        cursorUsageReader: @escaping @Sendable () async -> UsageSnapshot? = { nil },
        refreshTimeout: Duration = .seconds(180)
    ) {
        self.codexUsageSynchronizer = codexUsageSynchronizer
        self.codexUsagePreviewReader = codexUsagePreviewReader
        self.codexUsageReader = codexUsageReader
        self.claudeUsageReader = claudeUsageReader
        self.xaiUsageReader = xaiUsageReader
        self.cursorUsageReader = cursorUsageReader
        self.refreshTimeout = refreshTimeout
    }

    @discardableResult
    func refresh(
        force: Bool,
        refreshAllCodexAccounts: Bool = false,
        receive: @escaping Receiver
    ) -> Bool {
        guard inFlight == nil else {
            refreshQueued = refreshQueued || force
            refreshAllCodexAccountsQueued = refreshAllCodexAccountsQueued || refreshAllCodexAccounts
            return false
        }
        start(refreshAllCodexAccounts: refreshAllCodexAccounts, receive: receive)
        return true
    }

    func reset() {
        generation &+= 1
        inFlight?.workTask?.cancel()
        inFlight?.timeoutTask?.cancel()
        inFlight = nil
        refreshQueued = false
        refreshAllCodexAccountsQueued = false
    }

    private func start(
        refreshAllCodexAccounts: Bool,
        receive: @escaping Receiver
    ) {
        generation &+= 1
        let runGeneration = generation
        let codexUsageSynchronizer = codexUsageSynchronizer
        let codexUsagePreviewReader = codexUsagePreviewReader
        let codexUsageReader = codexUsageReader
        let claudeUsageReader = claudeUsageReader
        let xaiUsageReader = xaiUsageReader
        let cursorUsageReader = cursorUsageReader
        inFlight = Run(generation: runGeneration)

        let workTask = Task.detached(priority: .utility) { [weak self] in
            async let xaiUsage = xaiUsageReader()
            async let cursorUsage = cursorUsageReader()
            let syncResult: CodexUsageSyncResult
            var previewClaude: UsageSnapshot?
            if let codexUsagePreviewReader {
                async let pendingSyncResult = codexUsageSynchronizer(refreshAllCodexAccounts)
                let claude = claudeUsageReader()
                previewClaude = claude
                let codexPreview = codexUsagePreviewReader()
                guard !Task.isCancelled else { return }
                let preview = Result(
                    snapshots: [.codex: codexPreview, .claudeCode: claude],
                    accounts: codexPreview.accounts + claude.accounts,
                    points: codexPreview.points + claude.points,
                    tasks: codexPreview.tasks,
                    generation: runGeneration
                )
                await self?.publishProgress(preview, generation: runGeneration, receive: receive)
                syncResult = await pendingSyncResult
            } else {
                syncResult = await codexUsageSynchronizer(refreshAllCodexAccounts)
            }
            guard !Task.isCancelled else { return }
            var codex = codexUsageReader()
            guard !Task.isCancelled else { return }
            if let note = syncResult.note {
                codex.securityNotes.append(note)
            }
            let claude = previewClaude ?? claudeUsageReader()
            guard !Task.isCancelled else { return }
            let xai = await xaiUsage
            guard !Task.isCancelled else { return }
            let cursor = await cursorUsage
            guard !Task.isCancelled else { return }
            var snapshots: [UsageService: UsageSnapshot] = [.codex: codex, .claudeCode: claude]
            if let xai {
                snapshots[.xaiAPI] = xai
            }
            if let cursor {
                snapshots[.cursorAgent] = cursor
            }
            let result = Result(
                snapshots: snapshots,
                accounts: codex.accounts + claude.accounts + (xai?.accounts ?? []) + (cursor?.accounts ?? []),
                points: codex.points + claude.points + (xai?.points ?? []) + (cursor?.points ?? []),
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

    private func publishProgress(
        _ result: Result,
        generation runGeneration: UInt64,
        receive: @escaping Receiver
    ) {
        guard inFlight?.generation == runGeneration else { return }
        receive(.progress(result))
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
        let shouldRefreshAllCodexAccounts = refreshAllCodexAccountsQueued
        refreshQueued = false
        refreshAllCodexAccountsQueued = false
        if shouldRepeat {
            start(refreshAllCodexAccounts: shouldRefreshAllCodexAccounts, receive: receive)
        } else {
            receive(completion)
        }
    }
}
