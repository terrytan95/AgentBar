import XCTest
@testable import AgentBar

final class SettingsPersistenceTests: XCTestCase {
    @MainActor
    func testBackupIsDebouncedAndPersistsLatestValue() async throws {
        let suiteName = "SettingsPersistenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let persistenceURL = directory.appending(path: "Settings.plist")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        defaults.set(60.0, forKey: "refreshInterval")
        let store = SettingsStore(defaults: defaults, persistenceURL: persistenceURL)
        try await Task.sleep(for: .milliseconds(700))
        let initialData = try Data(contentsOf: persistenceURL)

        store.refreshInterval = 120
        store.refreshInterval = 180

        XCTAssertEqual(try Data(contentsOf: persistenceURL), initialData)
        try await Task.sleep(for: .milliseconds(700))
        let values = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: persistenceURL),
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(values["refreshInterval"] as? Double, 180)
    }

    @MainActor
    func testAllSettingsSurviveDefaultsReset() async throws {
        let suiteName = "SettingsPersistenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let persistenceURL = directory.appending(path: "Settings.plist")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let projectBudget = ProjectBudget(
            id: "project",
            dailyTokenLimit: 1_000,
            weeklyTokenLimit: 7_000,
            dailyCostLimitUSD: 2.5,
            weeklyCostLimitUSD: 12.5
        )
        let seededValues: [String: Any] = [
            "language": AppLanguage.chinese.rawValue,
            "refreshInterval": 300.0,
            "quotaCapacityHistoryInterval": 7_200.0,
            "launchAtLogin": true,
            "menuBarDisplayMode": MenuBarDisplayMode.totalTokens.rawValue,
            "showCodexInMenuBar": false,
            "showCodexSidebarQuotaOverlay": true,
            "codexSidebarQuotaOverlayIndependent": true,
            "quotaWidgetHotKey": Data(#"{"keyCode":8,"modifiers":2048,"keyLabel":"C"}"#.utf8),
            "didCompleteQuotaWidgetOnboarding": true,
            "showClaudeInMenuBar": false,
            "didMigrateActiveAccountMenuBarDefault": true,
            "useDarkAppearance": true,
            "useTranslucentAppearance": false,
            "accountSortMode": AccountSortMode.alphabetical.rawValue,
            "showAggregatedAccountData": true,
            "autoCodexAccountRotationEnabled": true,
            "quotaResetNotificationsEnabled": true,
            "taskCompletionNotificationsEnabled": true,
            "accessTokenExpiryNotificationsEnabled": true,
            "projectBudgets": try JSONEncoder().encode([projectBudget]),
            "codexRotationThresholdRemainingPercent": 25.0,
            "dailyTokenBudget": 2_000,
            "weeklyTokenBudget": 14_000,
            "dailyCostBudgetUSD": 5.0,
            "weeklyCostBudgetUSD": 25.0,
            "popoverHeight": 800.0
        ]
        seededValues.forEach { defaults.set($0.value, forKey: $0.key) }

        let initial = SettingsStore(defaults: defaults, persistenceURL: persistenceURL)
        initial.refreshInterval = 600
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistenceURL.path))

        defaults.removePersistentDomain(forName: suiteName)
        let restored = SettingsStore(defaults: defaults, persistenceURL: persistenceURL)

        XCTAssertEqual(restored.language, .chinese)
        XCTAssertEqual(restored.refreshInterval, 600)
        XCTAssertEqual(restored.quotaCapacityHistoryInterval, 7_200)
        XCTAssertTrue(restored.launchAtLogin)
        XCTAssertEqual(restored.menuBarDisplayMode, .totalTokens)
        XCTAssertFalse(restored.showCodexInMenuBar)
        XCTAssertTrue(restored.showCodexSidebarQuotaOverlay)
        XCTAssertTrue(restored.codexSidebarQuotaOverlayIndependent)
        XCTAssertEqual(restored.quotaWidgetHotKey?.keyCode, 8)
        XCTAssertEqual(restored.quotaWidgetHotKey?.modifiers, 2_048)
        XCTAssertEqual(restored.quotaWidgetHotKey?.keyLabel, "C")
        XCTAssertTrue(restored.didCompleteQuotaWidgetOnboarding)
        XCTAssertFalse(restored.showClaudeInMenuBar)
        XCTAssertTrue(restored.useDarkAppearance)
        XCTAssertFalse(restored.useTranslucentAppearance)
        XCTAssertEqual(restored.accountSortMode, .alphabetical)
        XCTAssertTrue(restored.showAggregatedAccountData)
        XCTAssertTrue(restored.autoCodexAccountRotationEnabled)
        XCTAssertTrue(restored.quotaResetNotificationsEnabled)
        XCTAssertTrue(restored.taskCompletionNotificationsEnabled)
        XCTAssertTrue(restored.accessTokenExpiryNotificationsEnabled)
        XCTAssertEqual(restored.projectBudgets, [projectBudget])
        XCTAssertEqual(restored.codexRotationThresholdRemainingPercent, 25)
        XCTAssertEqual(restored.dailyTokenBudget, 2_000)
        XCTAssertEqual(restored.weeklyTokenBudget, 14_000)
        XCTAssertEqual(restored.dailyCostBudgetUSD, 5)
        XCTAssertEqual(restored.weeklyCostBudgetUSD, 25)
        XCTAssertEqual(restored.popoverHeight, 800)
    }
}
