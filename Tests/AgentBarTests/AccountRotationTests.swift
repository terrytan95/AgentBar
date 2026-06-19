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

    func testSelectorPrefersResetCreditAccountBeforeLargestRemainingFallback() throws {
        let accounts = [
            account(id: "active", used: 95, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true),
            account(id: "reset-credit", used: 40, resetsAt: now.addingTimeInterval(1_800), lastUpdated: now, resetCredits: 1),
            account(id: "largest-remaining", used: 5, resetsAt: now.addingTimeInterval(3_600), lastUpdated: now)
        ]

        let selected = try XCTUnwrap(CodexAccountRotationPolicy(thresholdRemainingPercent: 10)
            .selectedAccount(from: accounts, now: now))

        XCTAssertEqual(selected.id, "reset-credit")
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
            codexUsageSynchronizer: { .success },
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
            codexUsageSynchronizer: { .success },
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

    @MainActor
    func testManualSwitchForceRestartsAndSuppressesImmediateAutoRotationOverride() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.autoCodexAccountRotationEnabled = true
        let switchExpectation = expectation(description: "manual switch completed")
        let recorder = AccountRotationRecorder()
        let store = UsageStore(
            settings: settings,
            codexUsageSynchronizer: { .success },
            codexAccountSwitcher: { accountID in
                recorder.recordSwitch(accountID)
            },
            automaticCodexRestarter: {
                XCTFail("Manual account selection should not use the automatic guarded restarter.")
                return .restarted
            },
            manualCodexAppRestarter: {
                recorder.recordRestart(.restarted)
                switchExpectation.fulfill()
            }
        )
        let active = account(id: "active", used: 95, resetsAt: now.addingTimeInterval(600), lastUpdated: now, isActive: true)
        let manual = account(id: "manual", used: 100, resetsAt: now.addingTimeInterval(300), lastUpdated: now, isActive: false)
        let automaticCandidate = account(id: "automatic-candidate", used: 5, resetsAt: now.addingTimeInterval(1_800), lastUpdated: now.addingTimeInterval(-20_000))
        store.applyTestData(accounts: [active, manual, automaticCandidate])

        store.switchActiveAccount(manual)
        wait(for: [switchExpectation], timeout: 2)

        XCTAssertEqual(recorder.switchedAccountID, "manual")
        XCTAssertEqual(recorder.restartResult, .restarted)

        recorder.reset()
        store.applyTestData(accounts: [
            account(id: "manual", used: 100, resetsAt: now.addingTimeInterval(300), lastUpdated: now, isActive: true),
            active,
            automaticCandidate
        ])

        store.evaluateAutomaticCodexRotation(now: now)

        XCTAssertNil(recorder.switchedAccountID)
        XCTAssertNil(recorder.restartResult)
    }

    @MainActor
    func testFailedManualSwitchPromptsCodexReloginWithPhoneAuthHintAndRetriesAfterRecovery() throws {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let promptExpectation = expectation(description: "login prompt shown")
        let retryExpectation = expectation(description: "failed account retried after recovery")
        let recorder = AccountRotationRecorder()
        let account = account(id: "locked", used: 50, resetsAt: now.addingTimeInterval(300), lastUpdated: now)
        let codexSnapshot = UsageSnapshot(
            service: .codex,
            status: .live,
            accounts: [account],
            points: [],
            securityNotes: [],
            refreshedAt: now,
            pricingFingerprint: Pricing.fingerprint
        )
        let store = UsageStore(
            settings: SettingsStore(defaults: defaults),
            codexUsageSynchronizer: { .success },
            codexUsageReader: { codexSnapshot },
            claudeUsageReader: {
                UsageSnapshot.empty(service: .claudeCode, status: .unavailable, note: "test")
            },
            codexAccountSwitcher: { accountID in
                recorder.recordSwitch(accountID)
                if recorder.consumeFailNextSwitch() {
                    throw AccountActionError.missingAccountSnapshot
                }
            },
            manualCodexAppRestarter: {
                recorder.recordRestart(.restarted)
                retryExpectation.fulfill()
            },
            codexAccountSwitchFailurePrompter: { recovery in
                recorder.recordPrompt(recovery)
                promptExpectation.fulfill()
            },
            codexAccountRecoveryLoginLauncher: { accountID, accountLabel in
                recorder.recordRecoveryLogin(accountID: accountID, accountLabel: accountLabel)
            }
        )
        store.applyTestData(accounts: [account])

        store.switchActiveAccount(account)
        wait(for: [promptExpectation], timeout: 2)

        let recovery = try XCTUnwrap(recorder.promptRecovery)
        XCTAssertEqual(recovery.accountID, "locked")
        XCTAssertEqual(recovery.accountLabel, "locked@example.com")
        let promptMessage = recovery.message
        XCTAssertTrue(promptMessage.contains("login to this Codex account again"))
        XCTAssertTrue(promptMessage.contains("phone number authentication might be needed"))

        recovery.startLogin()
        XCTAssertEqual(recorder.recoveryLoginAccountID, "locked")
        XCTAssertEqual(recorder.recoveryLoginAccountLabel, "locked@example.com")

        store.refresh(force: true)
        wait(for: [retryExpectation], timeout: 2)
        XCTAssertEqual(recorder.switchedAccountID, "locked")
        XCTAssertEqual(recorder.restartResult, .restarted)
    }

    private final class AccountRotationRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedSwitchAccountID: String?
        private var recordedRestartResult: CodexAppRestartResult?
        private var recordedPromptRecovery: CodexAccountSwitchRecovery?
        private var recordedRecoveryLoginAccountID: String?
        private var recordedRecoveryLoginAccountLabel: String?
        private var shouldFailNextSwitch = true

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

        var promptRecovery: CodexAccountSwitchRecovery? {
            lock.lock()
            defer { lock.unlock() }
            return recordedPromptRecovery
        }

        var recoveryLoginAccountID: String? {
            lock.lock()
            defer { lock.unlock() }
            return recordedRecoveryLoginAccountID
        }

        var recoveryLoginAccountLabel: String? {
            lock.lock()
            defer { lock.unlock() }
            return recordedRecoveryLoginAccountLabel
        }

        func recordSwitch(_ accountID: String) {
            lock.lock()
            recordedSwitchAccountID = accountID
            lock.unlock()
        }

        func consumeFailNextSwitch() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if shouldFailNextSwitch {
                shouldFailNextSwitch = false
                return true
            }
            return false
        }

        func recordRestart(_ result: CodexAppRestartResult) {
            lock.lock()
            recordedRestartResult = result
            lock.unlock()
        }

        func recordPrompt(_ recovery: CodexAccountSwitchRecovery) {
            lock.lock()
            recordedPromptRecovery = recovery
            lock.unlock()
        }

        func recordRecoveryLogin(accountID: String, accountLabel: String) {
            lock.lock()
            recordedRecoveryLoginAccountID = accountID
            recordedRecoveryLoginAccountLabel = accountLabel
            lock.unlock()
        }

        func reset() {
            lock.lock()
            recordedSwitchAccountID = nil
            recordedRestartResult = nil
            recordedPromptRecovery = nil
            recordedRecoveryLoginAccountID = nil
            recordedRecoveryLoginAccountLabel = nil
            shouldFailNextSwitch = true
            lock.unlock()
        }
    }

    private func account(
        id: String,
        service: UsageService = .codex,
        used: Double?,
        resetsAt: Date?,
        lastUpdated: Date?,
        isActive: Bool = false,
        resetCredits: Int = 0
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
            resetCredits: resetCredits > 0 ? UsageResetCredits(availableCount: resetCredits) : nil,
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: lastUpdated,
            isActive: isActive
        )
    }
}
