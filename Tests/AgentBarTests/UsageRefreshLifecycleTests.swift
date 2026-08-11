import XCTest
@testable import AgentBar

final class UsageRefreshLifecycleTests: XCTestCase {
    @MainActor
    func testQueuedRefreshPublishesOnlyFinalGeneration() async {
        let gate = RefreshGate()
        let lifecycle = makeLifecycle(gate: gate)
        let received = CompletionRecorder()
        let completed = expectation(description: "final refresh received")

        XCTAssertTrue(lifecycle.refresh(force: false) { completion in
            received.append(completion)
            completed.fulfill()
        })
        await waitForArrivals(1, at: gate)
        XCTAssertFalse(lifecycle.refresh(force: true, refreshAllCodexAccounts: true) { _ in
            XCTFail("queued refresh must retain the original receiver")
        })

        await gate.releaseNext()
        await waitForArrivals(2, at: gate)
        XCTAssertTrue(received.completions.isEmpty)

        await gate.releaseNext()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(received.completions.count, 1)
        guard case let .result(result) = received.completions[0] else {
            return XCTFail("expected a refresh result")
        }
        XCTAssertGreaterThan(result.generation, 1)
        let refreshScopes = await gate.refreshAllCodexAccounts
        XCTAssertEqual(refreshScopes, [false, true])
    }

    @MainActor
    func testTimeoutFinishesWhileBlockedWorkIsDiscarded() async {
        let gate = RefreshGate()
        let lifecycle = makeLifecycle(gate: gate, timeout: .milliseconds(30))
        let received = CompletionRecorder()
        let completed = expectation(description: "refresh timed out")

        XCTAssertTrue(lifecycle.refresh(force: false) { completion in
            received.append(completion)
            completed.fulfill()
        })
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(received.completions.count, 1)
        guard case .timedOut = received.completions[0] else {
            return XCTFail("expected timeout")
        }

        await gate.releaseAll()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(received.completions.count, 1)
    }

    @MainActor
    func testStoreInitIsIdleAndTestDataRejectsOldRefresh() async {
        let gate = RefreshGate()
        let oldPoint = point(total: 1)
        let testPoint = point(total: 2)
        let store = UsageStore(
            codexUsageSynchronizer: {
                await gate.wait()
                return .success
            },
            codexUsageReader: { snapshot(service: .codex, points: [oldPoint]) },
            codexTaskReader: { [] },
            claudeUsageReader: { snapshot(service: .claudeCode) },
            refreshTimeout: .seconds(1)
        )

        try? await Task.sleep(for: .milliseconds(550))
        let refreshCount = await gate.count
        XCTAssertEqual(refreshCount, 0)

        store.refresh(force: true)
        await waitForArrivals(1, at: gate)
        store.applyTestData(points: [testPoint])
        await gate.releaseNext()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.points, [testPoint])
        XCTAssertFalse(store.isRefreshing)
    }

    @MainActor
    func testProgressIncludesOptionalProvidersBeforeCodexSyncFinishes() async throws {
        let gate = RefreshGate()
        let grok = snapshot(service: .xaiAPI, accounts: [account(service: .xaiAPI)])
        let cursor = snapshot(service: .cursorAgent, accounts: [account(service: .cursorAgent)])
        let lifecycle = UsageRefreshLifecycle(
            codexUsageSynchronizer: { _ in
                await gate.wait()
                return .success
            },
            codexUsagePreviewReader: { snapshot(service: .codex) },
            codexUsageReader: { snapshot(service: .codex) },
            claudeUsageReader: { snapshot(service: .claudeCode) },
            xaiUsageReader: { grok },
            cursorUsageReader: { cursor },
            refreshTimeout: .seconds(1)
        )
        let progressReceived = expectation(description: "provider progress received")
        var progress: UsageRefreshLifecycle.Result?

        XCTAssertTrue(lifecycle.refresh(force: false) { completion in
            guard case let .progress(result) = completion else { return }
            progress = result
            progressReceived.fulfill()
        })
        await fulfillment(of: [progressReceived], timeout: 1)
        let result = try XCTUnwrap(progress)
        await gate.releaseAll()

        XCTAssertEqual(Set(result.snapshots.keys), Set(UsageService.allCases))
        XCTAssertEqual(Set(result.accounts.map(\.service)), Set([.xaiAPI, .cursorAgent]))
    }

    @MainActor
    private func makeLifecycle(
        gate: RefreshGate,
        timeout: Duration = .seconds(1)
    ) -> UsageRefreshLifecycle {
        UsageRefreshLifecycle(
            codexUsageSynchronizer: { refreshAllCodexAccounts in
                await gate.wait(refreshAllCodexAccounts: refreshAllCodexAccounts)
                return .success
            },
            codexUsageReader: { snapshot(service: .codex) },
            claudeUsageReader: { snapshot(service: .claudeCode) },
            refreshTimeout: timeout
        )
    }

    @MainActor
    private func waitForArrivals(_ expected: Int, at gate: RefreshGate) async {
        for _ in 0..<100 {
            if await gate.count >= expected { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("refresh work did not reach the gate")
    }
}

@MainActor
private final class CompletionRecorder {
    var completions: [UsageRefreshLifecycle.Completion] = []

    func append(_ completion: UsageRefreshLifecycle.Completion) {
        completions.append(completion)
    }
}

private actor RefreshGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var count = 0
    private(set) var refreshAllCodexAccounts: [Bool] = []

    func wait(refreshAllCodexAccounts: Bool = false) async {
        count += 1
        self.refreshAllCodexAccounts.append(refreshAllCodexAccounts)
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releaseNext() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private func snapshot(
    service: UsageService,
    points: [UsagePoint] = [],
    accounts: [UsageAccount] = []
) -> UsageSnapshot {
    UsageSnapshot(
        service: service,
        status: .live,
        accounts: accounts,
        points: points,
        securityNotes: [],
        refreshedAt: Date(),
        pricingFingerprint: Pricing.fingerprint
    )
}

private func account(service: UsageService) -> UsageAccount {
    UsageAccount(
        id: service.rawValue,
        service: service,
        displayName: service.rawValue,
        sourceDescription: "test",
        status: .live,
        tokens: .zero,
        isActive: true
    )
}

private func point(total: Int) -> UsagePoint {
    UsagePoint(
        service: .codex,
        model: "test",
        date: Date(),
        tokens: TokenTotals(
            input: total,
            cachedInput: 0,
            output: 0,
            reasoningOutput: 0,
            total: total
        ),
        estimatedCostUSD: nil
    )
}
