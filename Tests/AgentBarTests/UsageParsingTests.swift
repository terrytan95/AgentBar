import SwiftUI
import XCTest
@testable import AgentBar

final class UsageParsingTests: XCTestCase {
    func testCodexRegistryParsesMultipleAccountsWithoutSecrets() throws {
        let registry = """
        {
          "schema_version": 3,
          "active_account_key": "acct-a",
          "accounts": [
            {
              "account_key": "acct-a",
              "alias": "Work",
              "email": "person@example.com",
              "plan": "team",
              "last_usage_at": 1781388220,
              "last_usage": {
                "plan_type": "team",
                "primary": {"used_percent": 18, "window_minutes": 300, "resets_at": 1781400000},
                "secondary": {"used_percent": 51, "window_minutes": 10080, "resets_at": 1781900000}
              }
            },
            {
              "account_key": "acct-b",
              "account_name": "Personal",
              "auth_mode": "chatgpt",
              "plan": "plus"
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try CodexUsageReader.parseRegistry(data: registry, now: Date(timeIntervalSince1970: 1_781_388_300))

        XCTAssertEqual(snapshot.accounts.count, 2)
        XCTAssertEqual(snapshot.accounts[0].displayName, "person@example.com")
        XCTAssertEqual(snapshot.accounts[0].username, "person@example.com")
        XCTAssertEqual(snapshot.accounts[0].maskedEmail, "p***@example.com")
        XCTAssertEqual(snapshot.accounts[0].fiveHourWindow?.usedPercent, 18)
        XCTAssertEqual(snapshot.accounts[0].weeklyWindow?.usedPercent, 51)
        XCTAssertTrue(snapshot.accounts[0].isActive)
        XCTAssertEqual(snapshot.accounts[1].displayName, "Personal")
        XCTAssertEqual(snapshot.accounts[1].username, "Personal")
        XCTAssertFalse(snapshot.accounts[1].isActive)
        XCTAssertFalse(snapshot.securityNotes.joined(separator: " ").localizedCaseInsensitiveContains("token"))
    }

    func testCodexSessionJsonlAggregatesTokenUsageAndRateLimits() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","payload":{"info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":1,"total_tokens":13},"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":1,"total_tokens":13}},"rate_limits":{"primary":{"used_percent":5,"window_minutes":300,"resets_at":1781406270},"secondary":{"used_percent":3,"window_minutes":10080,"resets_at":1781894023},"plan_type":"team"}}}
        {"type":"event_msg","timestamp":"2026-06-13T22:06:23.246Z","payload":{"info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":4,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":25},"total_token_usage":{"input_tokens":30,"cached_input_tokens":6,"output_tokens":8,"reasoning_output_tokens":3,"total_tokens":38}},"rate_limits":{"primary":{"used_percent":7,"window_minutes":300,"resets_at":1781406270},"secondary":{"used_percent":4,"window_minutes":10080,"resets_at":1781894023},"plan_type":"team"}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.eventCount, 2)
        XCTAssertEqual(metrics.tokenTotals.input, 30)
        XCTAssertEqual(metrics.tokenTotals.cachedInput, 6)
        XCTAssertEqual(metrics.tokenTotals.output, 8)
        XCTAssertEqual(metrics.tokenTotals.reasoningOutput, 3)
        XCTAssertEqual(metrics.tokenTotals.total, 38)
        XCTAssertEqual(metrics.points.reduce(0) { $0 + $1.tokens.total }, 38)
        XCTAssertEqual(metrics.latestFiveHour?.usedPercent, 7)
        XCTAssertEqual(metrics.latestWeekly?.usedPercent, 4)
    }

    @MainActor
    func testRefreshingAfterInitialLoadDoesNotReturnAccountUIToLoadingState() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(settings: SettingsStore(defaults: defaults))
        store.applyTestData(accounts: [testAccount(id: "active", name: "active@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: Date())])

        store.refresh(force: true)

        XCTAssertTrue(store.hasLoadedAccountInformation)
        XCTAssertFalse(store.isLoadingAccountInformation)
    }

    @MainActor
    func testDarkThemeSettingPersistsAndToneColorCopyIsLocalized() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertFalse(settings.useDarkAppearance)
        settings.useDarkAppearance = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.useDarkAppearance)
        XCTAssertEqual(L.text("tone_color", .english), "Tone color")
        XCTAssertEqual(L.text("dark_theme", .chinese), "深色主题")
        XCTAssertEqual(AppAppearance.colorScheme(useDarkAppearance: false), .light)
        XCTAssertEqual(AppAppearance.colorScheme(useDarkAppearance: true), .dark)
    }

    @MainActor
    func testPopoverHeightPreferenceIsClampedWhenLoadedAndSaved() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(2_000, forKey: "popoverHeight")
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.popoverHeight, Double(PopoverLayout.maximumHeight))

        settings.popoverHeight = 120
        XCTAssertEqual(settings.popoverHeight, Double(PopoverLayout.minimumHeight))
        XCTAssertEqual(defaults.double(forKey: "popoverHeight"), Double(PopoverLayout.minimumHeight))

        settings.updatePopoverMaximumHeight(1_440)
        settings.popoverHeight = 1_200
        XCTAssertEqual(settings.popoverHeight, 1_200)
        XCTAssertEqual(defaults.double(forKey: "popoverHeight"), 1_200)
    }

    func testCodexReadPrefersLatestSessionRateLimitsForActiveAccount() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/06")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {
          "schema_version": 3,
          "active_account_key": "active",
          "accounts": [
            {
              "account_key": "active",
              "email": "active@example.com",
              "plan": "team",
              "last_usage": {
                "primary": {"used_percent": 90, "window_minutes": 300, "resets_at": 1781400000},
                "secondary": {"used_percent": 80, "window_minutes": 10080, "resets_at": 1781900000}
              }
            },
            {
              "account_key": "inactive",
              "email": "inactive@example.com",
              "plan": "team",
              "last_usage": {
                "primary": {"used_percent": 40, "window_minutes": 300, "resets_at": 1781400000},
                "secondary": {"used_percent": 30, "window_minutes": 10080, "resets_at": 1781900000}
              }
            }
          ]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:00:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":12,"window_minutes":300,"resets_at":1781410000},"secondary":{"used_percent":34,"window_minutes":10080,"resets_at":1781910000},"plan_type":"team"}}}
        """.data(using: .utf8)!.write(to: sessionDir.appending(path: "current.jsonl"))

        let snapshot = CodexUsageReader(homeDirectory: temp).read()
        let active = try XCTUnwrap(snapshot.accounts.first { $0.id == "active" })
        let inactive = try XCTUnwrap(snapshot.accounts.first { $0.id == "inactive" })

        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 12)
        XCTAssertEqual(active.weeklyWindow?.usedPercent, 34)
        XCTAssertEqual(inactive.fiveHourWindow?.usedPercent, 40)
        XCTAssertEqual(inactive.weeklyWindow?.usedPercent, 30)
    }

    func testCodexReadUsesNewestRateLimitEventAcrossSessionFiles() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/06")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"schema_version":3,"active_account_key":"active","accounts":[{"account_key":"active","email":"active@example.com","plan":"team"}]}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","timestamp":"2026-06-14T05:00:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":70,"window_minutes":300,"resets_at":1781400000},"secondary":{"used_percent":60,"window_minutes":10080,"resets_at":1781900000},"plan_type":"team"}}}
        """.data(using: .utf8)!.write(to: sessionDir.appending(path: "z-older.jsonl"))
        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:00:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":9,"window_minutes":300,"resets_at":1781410000},"secondary":{"used_percent":11,"window_minutes":10080,"resets_at":1781910000},"plan_type":"team"}}}
        """.data(using: .utf8)!.write(to: sessionDir.appending(path: "a-newer.jsonl"))

        let snapshot = CodexUsageReader(homeDirectory: temp).read()
        let active = try XCTUnwrap(snapshot.accounts.first)

        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 9)
        XCTAssertEqual(active.weeklyWindow?.usedPercent, 11)
    }

    func testCodexSessionMetricsCacheInvalidatesWhenFileChanges() throws {
        CodexUsageReader.resetSessionMetricsCacheForTesting()
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temp)
            CodexUsageReader.resetSessionMetricsCacheForTesting()
        }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/06")
        let sessionFile = sessionDir.appending(path: "current.jsonl")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"schema_version":3,"active_account_key":"active","accounts":[{"account_key":"active","email":"active@example.com","plan":"team"}]}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:00:00Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1781410000},"secondary":{"used_percent":20,"window_minutes":10080,"resets_at":1781910000}}}}
        """.data(using: .utf8)!.write(to: sessionFile)

        var snapshot = CodexUsageReader(homeDirectory: temp).read()
        XCTAssertEqual(snapshot.accounts.first?.fiveHourWindow?.usedPercent, 10)
        XCTAssertEqual(snapshot.points.reduce(0) { $0 + $1.tokens.total }, 2)

        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:00:00Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1781410000},"secondary":{"used_percent":20,"window_minutes":10080,"resets_at":1781910000}}}}
        {"type":"event_msg","timestamp":"2026-06-14T07:00:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":3,"cached_input_tokens":0,"output_tokens":4,"reasoning_output_tokens":0,"total_tokens":7}},"rate_limits":{"primary":{"used_percent":35,"window_minutes":300,"resets_at":1781420000},"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1781920000}}}}
        """.data(using: .utf8)!.write(to: sessionFile)

        snapshot = CodexUsageReader(homeDirectory: temp).read()

        XCTAssertEqual(snapshot.accounts.first?.fiveHourWindow?.usedPercent, 35)
        XCTAssertEqual(snapshot.accounts.first?.weeklyWindow?.usedPercent, 45)
        XCTAssertEqual(snapshot.points.reduce(0) { $0 + $1.tokens.total }, 9)
    }

    func testCodexSessionMetricsCacheDropsDeletedFiles() throws {
        CodexUsageReader.resetSessionMetricsCacheForTesting()
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temp)
            CodexUsageReader.resetSessionMetricsCacheForTesting()
        }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/06")
        let sessionFile = sessionDir.appending(path: "deleted.jsonl")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"schema_version":3,"active_account_key":"active","accounts":[{"account_key":"active","email":"active@example.com","plan":"team"}]}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:00:00Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1781410000},"secondary":{"used_percent":20,"window_minutes":10080,"resets_at":1781910000}}}}
        """.data(using: .utf8)!.write(to: sessionFile)

        var snapshot = CodexUsageReader(homeDirectory: temp).read()
        XCTAssertEqual(snapshot.points.count, 1)

        try FileManager.default.removeItem(at: sessionFile)
        snapshot = CodexUsageReader(homeDirectory: temp).read()

        XCTAssertTrue(snapshot.points.isEmpty)
        XCTAssertNil(snapshot.accounts.first?.fiveHourWindow)
    }

    func testCodexReadKeepsSwitchedAccountWindowsWhenLatestSessionPredatesActivation() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/06")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {
          "schema_version": 3,
          "active_account_key": "new-active",
          "active_account_activated_at_ms": 1781420400000,
          "accounts": [
            {
              "account_key": "old-active",
              "email": "old@example.com",
              "last_usage": {
                "primary": {"used_percent": 90, "window_minutes": 300, "resets_at": 1781400000},
                "secondary": {"used_percent": 80, "window_minutes": 10080, "resets_at": 1781900000}
              }
            },
            {
              "account_key": "new-active",
              "email": "new@example.com",
              "last_usage": {
                "primary": {"used_percent": 22, "window_minutes": 300, "resets_at": 1781410000},
                "secondary": {"used_percent": 44, "window_minutes": 10080, "resets_at": 1781910000}
              }
            }
          ]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:30:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":91,"window_minutes":300,"resets_at":1781400000},"secondary":{"used_percent":81,"window_minutes":10080,"resets_at":1781900000},"plan_type":"team"}}}
        """.data(using: .utf8)!.write(to: sessionDir.appending(path: "previous-account.jsonl"))

        let snapshot = CodexUsageReader(homeDirectory: temp).read()
        let active = try XCTUnwrap(snapshot.accounts.first { $0.id == "new-active" })

        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 22)
        XCTAssertEqual(active.weeklyWindow?.usedPercent, 44)
    }

    func testOpenAIModelPricingCalculatesPointCost() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","payload":{"info":{"model":"gpt-5.1","last_token_usage":{"input_tokens":1000000,"cached_input_tokens":100000,"output_tokens":100000,"reasoning_output_tokens":0,"total_tokens":1100000}}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.points.count, 1)
        XCTAssertEqual(metrics.points[0].estimatedCostUSD ?? 0, Decimal(string: "2.1375"))
    }

    func testPricingNormalizesProviderAndDateSuffixes() {
        XCTAssertEqual(Pricing.normalize(model: "openai/GPT-5.4@20260131"), "gpt-5.4")
        XCTAssertEqual(Pricing.normalize(model: "claude-sonnet-4-5-20260229"), "claude-sonnet-4-5")
        XCTAssertEqual(Pricing.normalize(model: "claude-opus-4-7-2026-02-29"), "claude-opus-4-7")
    }

    func testPricingUsesDecimalAndUnknownModelsCostZeroButKeepTokens() {
        let unknown = Pricing.cost(model: "codex-auto-review", input: 99_000_000, output: 1_000_000, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(unknown, 0)

        let known = Pricing.cost(model: "openai/gpt-5.4@20260131", input: 1_000_000, output: 100_000, cacheRead: 100_000, cacheCreation: 0)
        XCTAssertEqual(known, Decimal(string: "4.025"))
    }

    func testPricingFingerprintIsStableSHA256AndIncludedInSummary() {
        XCTAssertEqual(Pricing.fingerprint.count, 64)
        XCTAssertTrue(Pricing.fingerprint.allSatisfy { $0.isHexDigit })

        let summary = UsageStatistics.summarize(points: [], range: .all)
        XCTAssertEqual(summary.pricingFingerprint, Pricing.fingerprint)
    }

    @MainActor
    func testMenuBarDefaultsToActiveAccountQuotaWindows() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let store = UsageStore(settings: settings)
        let now = Date()
        store.applyTestData(accounts: [
            UsageAccount(
                id: "inactive",
                service: .codex,
                displayName: "inactive@example.com",
                username: "inactive@example.com",
                maskedEmail: nil,
                plan: "team",
                sourceDescription: "test",
                status: .live,
                fiveHourWindow: UsageWindow(kind: .fiveHour, usedPercent: 90, windowMinutes: 300, resetsAt: now),
                weeklyWindow: UsageWindow(kind: .weekly, usedPercent: 40, windowMinutes: 10080, resetsAt: now),
                tokens: .zero,
                estimatedCostUSD: nil,
                lastUpdated: now,
                isActive: false
            ),
            UsageAccount(
                id: "active",
                service: .codex,
                displayName: "active@example.com",
                username: "active@example.com",
                maskedEmail: nil,
                plan: "team",
                sourceDescription: "test",
                status: .live,
                fiveHourWindow: UsageWindow(kind: .fiveHour, usedPercent: 31, windowMinutes: 300, resetsAt: now),
                weeklyWindow: UsageWindow(kind: .weekly, usedPercent: 8, windowMinutes: 10080, resetsAt: now),
                tokens: .zero,
                estimatedCostUSD: nil,
                lastUpdated: now,
                isActive: true
            )
        ])

        XCTAssertEqual(settings.menuBarDisplayMode, .activeAccountWindows)
        XCTAssertEqual(store.menuBarTitle, "5H 69%  WK 92%")
    }

    @MainActor
    func testPopoverHeaderShowsActiveAccountFiveHourAndWeeklyRemaining() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let store = UsageStore(settings: settings)
        let now = Date()
        store.applyTestData(accounts: [
            testAccount(id: "empty", name: "empty@example.com", fiveHourUsed: 100, weeklyUsed: 100, now: now),
            {
                var account = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 1, weeklyUsed: 8, now: now)
                account.isActive = true
                return account
            }()
        ])

        XCTAssertEqual(store.popoverHeaderQuotaTitle, "5H 99% remaining · WK 92% remaining")
    }

    @MainActor
    func testMenuBarDisplayModeMigratesExistingInstallToActiveAccountWindows() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MenuBarDisplayMode.lowestRemaining.rawValue, forKey: "menuBarDisplayMode")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.menuBarDisplayMode, .activeAccountWindows)
    }

    func testStatisticsBucketsAggregateExpectedRanges() {
        let calendar = Calendar(identifier: .gregorian)
        let now = ISO8601DateFormatter().date(from: "2026-06-13T22:00:00Z")!
        let points = [
            UsagePoint(service: .codex, model: "gpt-5.4", date: now, tokens: TokenTotals(input: 10, cachedInput: 0, output: 2, reasoningOutput: 0, total: 12), estimatedCostUSD: 0.001),
            UsagePoint(service: .codex, model: "gpt-5.4-mini", date: calendar.date(byAdding: .day, value: -1, to: now)!, tokens: TokenTotals(input: 20, cachedInput: 0, output: 4, reasoningOutput: 0, total: 24), estimatedCostUSD: 0.002),
            UsagePoint(service: .claudeCode, model: "unavailable", date: calendar.date(byAdding: .day, value: -10, to: now)!, tokens: TokenTotals(input: 30, cachedInput: 0, output: 6, reasoningOutput: 0, total: 36), estimatedCostUSD: nil)
        ]

        let today = UsageStatistics.summarize(points: points, range: .today, now: now, calendar: calendar)
        let sevenDays = UsageStatistics.summarize(points: points, range: .last7Days, now: now, calendar: calendar)
        let all = UsageStatistics.summarize(points: points, range: .all, now: now, calendar: calendar)

        XCTAssertEqual(today.totalTokens, 12)
        XCTAssertEqual(sevenDays.totalTokens, 36)
        XCTAssertEqual(all.totalTokens, 72)
        XCTAssertEqual(all.serviceBreakdown[.codex], 36)
        XCTAssertEqual(all.serviceBreakdown[.claudeCode], 36)
    }

    func testAccountSortingUsesFiveHourThenWeeklyPressure() {
        let now = Date()
        let accounts = [
            testAccount(id: "a", name: "a@example.com", fiveHourUsed: 1, weeklyUsed: 10, now: now),
            testAccount(id: "b", name: "b@example.com", fiveHourUsed: 100, weeklyUsed: 1, now: now),
            testAccount(id: "c", name: "c@example.com", fiveHourUsed: 1, weeklyUsed: 40, now: now)
        ]

        let sorted = accounts.sorted(using: .quotaPressure)

        XCTAssertEqual(sorted.map(\.id), ["b", "c", "a"])
    }

    func testAccountSortingAlwaysKeepsActiveAccountOnTop() {
        let now = Date()
        var active = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 1, weeklyUsed: 1, now: now)
        active.isActive = true
        let constrained = testAccount(id: "constrained", name: "constrained@example.com", fiveHourUsed: 100, weeklyUsed: 100, now: now)

        let sorted = [constrained, active].sorted(using: .quotaPressure)

        XCTAssertEqual(sorted.map(\.id), ["active", "constrained"])
    }

    func testEnglishCompactTokenFormattingUsesEnglishUnits() {
        XCTAssertEqual(DisplayFormatters.compactTokenString(63_229_600, language: .english), "63.2296 mil")
        XCTAssertEqual(DisplayFormatters.compactTokenString(6_322_960_000, language: .english), "6.3230 bil")
    }

    func testDailyUsageBarTooltipIncludesDateAndUsageDetails() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let bar = DailyUsageBar(day: day, codexTokens: 1_500_000, claudeTokens: 2_000_000)

        let tooltip = bar.tooltipText(language: .english)

        XCTAssertTrue(tooltip.contains("Jun 13, 2026"))
        XCTAssertTrue(tooltip.contains("Codex: 1.5000 mil Tokens"))
        XCTAssertTrue(tooltip.contains("Claude: 2.0000 mil Tokens"))
        XCTAssertTrue(tooltip.contains("Total: 3.5000 mil Tokens"))
    }

    func testAccountMetadataShowsResetActivityAndAccountType() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let account = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 1, weeklyUsed: 8, now: now)

        XCTAssertTrue(account.accountTypeLine(language: .english).contains("Account type: TEAM"))
        XCTAssertTrue(account.lastActivityLine(language: .english).contains("Last activity:"))
        XCTAssertTrue(account.fiveHourWindow?.resetLine(language: .english).contains("Reset:") == true)
    }

    func testCodexAccountSwitcherCopiesSnapshotToActiveAuthAndTracksPrevious() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registry = accountDir.appending(path: "registry.json")
        let targetAccountID = "user-alpha::acct-b"
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-a","email":"a@example.com"},{"account_key":"\(targetAccountID)","email":"b@example.com"}]}
        """.data(using: .utf8)!.write(to: registry)
        let activeAuth = temp.appending(path: ".codex/auth.json")
        try "old active auth".data(using: .utf8)!.write(to: activeAuth)
        let encodedFileKey = Data(targetAccountID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        try "selected account auth".data(using: .utf8)!.write(to: accountDir.appending(path: "\(encodedFileKey).auth.json"))
        defer { try? FileManager.default.removeItem(at: temp) }

        try CodexAccountSwitcher(homeDirectory: temp).switchActiveAccount(accountID: targetAccountID)
        let data = try Data(contentsOf: registry)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["active_account_key"] as? String, targetAccountID)
        XCTAssertEqual(json["previous_active_account_key"] as? String, "acct-a")
        XCTAssertEqual(json["schema_version"] as? Int, 3)
        XCTAssertEqual((json["accounts"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(try String(contentsOf: activeAuth, encoding: .utf8), "selected account auth")
    }

    private func testAccount(id: String, name: String, fiveHourUsed: Double, weeklyUsed: Double, now: Date) -> UsageAccount {
        UsageAccount(
            id: id,
            service: .codex,
            displayName: name,
            username: name,
            maskedEmail: nil,
            plan: "team",
            sourceDescription: "test",
            status: .live,
            fiveHourWindow: UsageWindow(kind: .fiveHour, usedPercent: fiveHourUsed, windowMinutes: 300, resetsAt: now),
            weeklyWindow: UsageWindow(kind: .weekly, usedPercent: weeklyUsed, windowMinutes: 10080, resetsAt: now),
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: now,
            isActive: false
        )
    }
}
