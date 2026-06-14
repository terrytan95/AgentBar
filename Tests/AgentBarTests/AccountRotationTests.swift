import XCTest
@testable import AgentBar

final class AccountRotationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSelectorReturnsNilWhenActiveAccountIsNotNearFiveHourLimit() {
        let accounts = [
            account(id: "active", used: 80, resetsAt: now.addingTimeInterval(900), lastUpdated: now, isActive: true),
            account(id: "candidate", used: 5, resetsAt: now.addingTimeInterval(1_800), lastUpdated: now.addingTimeInterval(-20_000))
        ]

        let selected = CodexAccountRotationPolicy(thresholdRemainingPercent: 10)
            .selectedAccount(from: accounts, now: now)

        XCTAssertNil(selected)
    }

    func testSelectorPrefersUnusedSinceLastResetAccountWithClosestResetTime() throws {
        let fartherUnused = account(
            id: "farther-unused",
            used: 60,
            resetsAt: now.addingTimeInterval(12_000),
            lastUpdated: now.addingTimeInterval(-30_000)
        )
        let closerUnused = account(
            id: "closer-unused",
            used: 92,
            resetsAt: now.addingTimeInterval(3_600),
            lastUpdated: now.addingTimeInterval(-30_000)
        )
        let largerRemainingButAlreadyUsed = account(
            id: "already-used",
            used: 5,
            resetsAt: now.addingTimeInterval(1_800),
            lastUpdated: now
        )
        let accounts = [
            account(id: "active", used: 94, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true),
            fartherUnused,
            closerUnused,
            largerRemainingButAlreadyUsed
        ]

        let selected = try XCTUnwrap(CodexAccountRotationPolicy(thresholdRemainingPercent: 10)
            .selectedAccount(from: accounts, now: now))

        XCTAssertEqual(selected.id, "closer-unused")
    }

    func testSelectorFallsBackToLargestFiveHourRemainingWhenNoUnusedAccountExists() throws {
        let accounts = [
            account(id: "active", used: 95, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true),
            account(id: "low-remaining", used: 70, resetsAt: now.addingTimeInterval(1_800), lastUpdated: now),
            account(id: "largest-remaining", used: 25, resetsAt: now.addingTimeInterval(7_200), lastUpdated: now),
            account(id: "middle-remaining", used: 55, resetsAt: now.addingTimeInterval(3_600), lastUpdated: now)
        ]

        let selected = try XCTUnwrap(CodexAccountRotationPolicy(thresholdRemainingPercent: 10)
            .selectedAccount(from: accounts, now: now))

        XCTAssertEqual(selected.id, "largest-remaining")
    }

    func testSelectorUsesUnknownResetAccountOnlyAsFallback() throws {
        let unknownReset = account(id: "unknown-reset", used: 10, resetsAt: nil, lastUpdated: nil)
        let unusedKnownReset = account(
            id: "unused-known-reset",
            used: 90,
            resetsAt: now.addingTimeInterval(5_400),
            lastUpdated: now.addingTimeInterval(-40_000)
        )
        let accounts = [
            account(id: "active", used: 96, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true),
            unknownReset,
            unusedKnownReset
        ]

        let selected = try XCTUnwrap(CodexAccountRotationPolicy(thresholdRemainingPercent: 10)
            .selectedAccount(from: accounts, now: now))

        XCTAssertEqual(selected.id, "unused-known-reset")
    }

    func testSelectorIgnoresMissingQuotaDataAndActiveAccount() {
        let accounts = [
            account(id: "active", used: 97, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true),
            account(id: "missing-quota", used: nil, resetsAt: nil, lastUpdated: nil),
            account(id: "claude", service: .claudeCode, used: 1, resetsAt: now.addingTimeInterval(600), lastUpdated: nil)
        ]

        let selected = CodexAccountRotationPolicy(thresholdRemainingPercent: 10)
            .selectedAccount(from: accounts, now: now)

        XCTAssertNil(selected)
    }

    func testSelectorReturnsNilWhenNoActiveCodexAccountExists() {
        let accounts = [
            account(id: "candidate", used: 2, resetsAt: now.addingTimeInterval(600), lastUpdated: nil)
        ]

        let selected = CodexAccountRotationPolicy(thresholdRemainingPercent: 10)
            .selectedAccount(from: accounts, now: now)

        XCTAssertNil(selected)
    }

    func testRestartGuardDoesNotRestartWhenCodexWorkIsRunning() {
        let recorder = AccountRotationRecorder()
        let restarter = CodexAppRestarter(
            activityDetector: { true },
            restartCodexApp: { recorder.recordRestart(.restarted) }
        )

        let result = restarter.restartIfNoWorkIsRunning()

        XCTAssertEqual(result, .skippedWorkRunning)
        XCTAssertNil(recorder.restartResult)
    }

    func testRestartGuardForceRestartsWhenNoCodexWorkIsRunning() {
        let recorder = AccountRotationRecorder()
        let restarter = CodexAppRestarter(
            activityDetector: { false },
            restartCodexApp: { recorder.recordRestart(.restarted) }
        )

        let result = restarter.restartIfNoWorkIsRunning()

        XCTAssertEqual(result, .restarted)
        XCTAssertEqual(recorder.restartResult, .restarted)
    }

    func testProcessDetectorTreatsCodexCliRunAsWorkButIgnoresCodexAppProcess() {
        let detector = CodexWorkActivityDetector(
            processLines: {
                [
                    "/Applications/Codex.app/Contents/MacOS/Codex",
                    "/opt/homebrew/bin/codex run --model gpt-5",
                    "/Applications/AgentBar.app/Contents/MacOS/AgentBar"
                ]
            }
        )

        XCTAssertTrue(detector.hasRunningCodexWork())
    }

    func testProcessDetectorIgnoresCodexAppWhenNoCliWorkIsRunning() {
        let detector = CodexWorkActivityDetector(
            processLines: {
                [
                    "/Applications/Codex.app/Contents/MacOS/Codex",
                    "/Applications/AgentBar.app/Contents/MacOS/AgentBar"
                ]
            }
        )

        XCTAssertFalse(detector.hasRunningCodexWork())
    }

    @MainActor
    func testSettingsDefaultDisablesAutoRotationWithConservativeThreshold() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)

        XCTAssertFalse(settings.autoCodexAccountRotationEnabled)
        XCTAssertEqual(settings.codexRotationThresholdRemainingPercent, 10)
    }

    @MainActor
    func testSettingsPersistAutoRotationThresholdAndEnabledState() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)

        settings.autoCodexAccountRotationEnabled = true
        settings.codexRotationThresholdRemainingPercent = 15

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.autoCodexAccountRotationEnabled)
        XCTAssertEqual(reloaded.codexRotationThresholdRemainingPercent, 15)
    }

    @MainActor
    func testUsageStoreAutomaticallySwitchesAndSafelyRestartsWhenActiveCodexBelowThreshold() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.autoCodexAccountRotationEnabled = true
        let expectation = expectation(description: "automatic switch completed")
        let recorder = AccountRotationRecorder()
        let store = UsageStore(
            settings: settings,
            codexAccountSwitcher: { accountID in
                recorder.recordSwitch(accountID)
            },
            automaticCodexRestarter: {
                recorder.recordRestart(.restarted)
                expectation.fulfill()
                return .restarted
            }
        )
        store.applyTestData(accounts: [
            account(id: "active", used: 95, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true),
            account(id: "candidate", used: 5, resetsAt: now.addingTimeInterval(1_800), lastUpdated: now.addingTimeInterval(-20_000))
        ])

        store.evaluateAutomaticCodexRotation(now: now)

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(recorder.switchedAccountID, "candidate")
        XCTAssertEqual(recorder.restartResult, .restarted)
    }

    @MainActor
    func testUsageStoreDoesNotAutomaticallySwitchWhenAutoRotationIsDisabled() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.autoCodexAccountRotationEnabled = false
        let store = UsageStore(
            settings: settings,
            codexAccountSwitcher: { _ in XCTFail("Auto rotation should not switch when disabled.") },
            automaticCodexRestarter: {
                XCTFail("Auto rotation should not restart Codex when disabled.")
                return .restarted
            }
        )
        store.applyTestData(accounts: [
            account(id: "active", used: 95, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true),
            account(id: "candidate", used: 5, resetsAt: now.addingTimeInterval(1_800), lastUpdated: now.addingTimeInterval(-20_000))
        ])

        store.evaluateAutomaticCodexRotation(now: now)

        XCTAssertNil(store.switchingAccountID)
    }

    private final class AccountRotationRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedSwitchAccountID: String?
        private var recordedRestartResult: CodexAppRestartResult?

        var switchedAccountID: String? {
            lock.lock()
            defer { lock.unlock() }
            return recordedSwitchAccountID
        }

        var restartResult: CodexAppRestartResult? {
            lock.lock()
            defer { lock.unlock() }
            return recordedRestartResult
        }

        func recordSwitch(_ accountID: String) {
            lock.lock()
            recordedSwitchAccountID = accountID
            lock.unlock()
        }

        func recordRestart(_ result: CodexAppRestartResult) {
            lock.lock()
            recordedRestartResult = result
            lock.unlock()
        }
    }

    private func account(
        id: String,
        service: UsageService = .codex,
        used: Double?,
        resetsAt: Date?,
        lastUpdated: Date?,
        isActive: Bool = false
    ) -> UsageAccount {
        UsageAccount(
            id: id,
            service: service,
            displayName: "\(id)@example.com",
            username: "\(id)@example.com",
            maskedEmail: nil,
            plan: "team",
            sourceDescription: "test",
            status: .live,
            fiveHourWindow: used.map {
                UsageWindow(kind: .fiveHour, usedPercent: $0, windowMinutes: 300, resetsAt: resetsAt)
            },
            weeklyWindow: nil,
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: lastUpdated,
            isActive: isActive
        )
    }
}
