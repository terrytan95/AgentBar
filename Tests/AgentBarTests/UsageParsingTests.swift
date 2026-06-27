import SwiftUI
import XCTest
@testable import AgentBar

final class UsageParsingTests: XCTestCase {

    @MainActor
    func testUsageParsingCoverage() throws {
        try checkCodexRegistryParsesMultipleAccountsWithoutSecrets()
        try checkCodexRegistryParsesMultipleWorkspacesForOneAccount()
        checkAccountsWithSameIdentityGroupForDisplayWithoutMergingWorkspaceRows()
        try checkCodexRegistryFlagsAccountsThatNeedLoginAgain()
        try checkCodexReadClearsStale401AfterNewerAuthSnapshot()
        try checkCodexSessionJsonlAggregatesTokenUsageAndRateLimits()
        try checkCodexSessionJsonlUsesTurnContextModelForCostBreakdown()
        try checkCodexSessionJsonlParsesResetCreditsFromRateLimitEvents()
        try checkCodexSessionJsonlCarriesSessionAndProjectMetadata()
        try checkCodexSessionJsonlDerivesDailyUsageAcrossQuotaReset()
        try checkCodexUsageAPISyncerUpdatesRegistryWithoutCodexAuthRuntime()
        try checkCodexUsageAPISyncerRefreshesOnlyActiveAccount()
        try checkCodexUsageAPISyncerOptInFetchesDetailedResetExpiryDates()
        try checkCodexUsageAPISyncerPersists401AndClearsItAfterSuccess()
        try checkCodexUsageAPISyncerUsesNewerActiveAuthForActiveAccount()
        checkCodexRecoveryLoginCommandSavesActiveAuthToSelectedSnapshot()
        checkCodexAccountStorageCentralizesRegistryAuthAndRecoveryPaths()
        checkRefreshingAfterInitialLoadDoesNotReturnAccountUIToLoadingState()
        checkRefreshSyncsCodexUsageAPIBeforeReadingUsage()
        checkUsageRefreshOrchestratorSyncsBeforeReadersAndMergesSnapshots()
        checkCodexUsageSourceSyncsBeforeReadAndAppendsSyncNote()
        checkDarkThemeSettingPersistsAndToneColorCopyIsLocalized()
        checkPopoverHeightPreferenceIsClampedWhenLoadedAndSaved()
        try checkCodexReadPrefersRegistryUsageOverLocalSessionRateLimits()
        try checkCodexReadUsesNewestRateLimitEventAcrossSessionFiles()
        try checkCodexSessionMetricsCacheInvalidatesWhenFileChanges()
        try checkCodexSessionMetricsCacheDropsDeletedFiles()
        try checkCodexReadKeepsSwitchedAccountWindowsWhenLatestSessionPredatesActivation()
        try checkSessionRateLimitsWithoutParsableTimestampDoNotOverrideActiveAccountWindows()
        try checkOversizedSessionFilesAreSkipped()
        try checkOpenAIModelPricingCalculatesPointCost()
        checkPricingNormalizesProviderAndDateSuffixes()
        checkPricingUsesDecimalAndUnknownModelsCostZeroButKeepTokens()
        checkPricingFingerprintIsStableSHA256AndIncludedInSummary()
        checkMenuBarDefaultsToActiveAccountQuotaWindows()
        checkPopoverHeaderShowsActiveAccountFiveHourAndWeeklyRemaining()
        checkMenuBarDisplayModeMigratesExistingInstallToActiveAccountWindows()
        checkBudgetSettingsPersistAndWarnInMenuBarTitle()
        checkRapidUsageAlertWarnsInMenuBarTitle()
        checkStatisticsBucketsAggregateExpectedRanges()
        checkPeriodChangeComparesSelectedRangeAgainstPreviousPeriod()
        checkPeriodChangeHasNoPercentWithoutComparableBaseline()
        try checkUsageRangeIntervalsDriveStatisticsAndAuditFiltering()
        checkChangePercentFormattingShowsDirectionAndMissingBaseline()
        checkAccountSortingUsesFiveHourThenWeeklyPressure()
        checkAccountSortingPrioritizesResetCreditsAfterActiveAccount()
        checkAccountSortingAlwaysKeepsActiveAccountOnTop()
        checkEnglishCompactTokenFormattingUsesEnglishUnits()
        checkDailyUsageBarTooltipIncludesDateAndUsageDetails()
        checkAccountMetadataShowsResetActivityAndAccountType()
        try checkCodexAccountSwitcherCopiesSnapshotToActiveAuthAndTracksPrevious()
        try checkCodexAccountSwitcherRestoresAuthWhenRegistryWriteFails()
    }
    private func checkCodexRegistryParsesMultipleAccountsWithoutSecrets() throws {
        let registry = """
        {
          "schema_version": 3,
          "active_account_key": "user-a::workspace-a",
          "accounts": [
            {
              "account_key": "user-a::workspace-a",
              "alias": "Work",
              "email": "person@example.com",
              "account_name": "Team Workspace",
              "chatgpt_account_id": "workspace-a",
              "plan": "team",
              "last_usage_at": 1781388220,
              "last_usage": {
                "plan_type": "team",
                "primary": {"used_percent": 18, "window_minutes": 300, "resets_at": 1781400000},
                "secondary": {"used_percent": 51, "window_minutes": 10080, "resets_at": 1781900000},
                "reset_credits": {
                  "available_count": 2,
                  "resets": [{"expires_at": 1782000000}]
                }
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
        XCTAssertEqual(snapshot.accounts[0].workspaceName, "Team Workspace")
        XCTAssertEqual(snapshot.accounts[0].workspaceID, "workspace-a")
        XCTAssertEqual(snapshot.accounts[0].workspaceLine(language: .english), "Workspace: Team Workspace · workspace-a")
        XCTAssertEqual(snapshot.accounts[0].fiveHourWindow?.usedPercent, 18)
        XCTAssertEqual(snapshot.accounts[0].weeklyWindow?.usedPercent, 51)
        XCTAssertEqual(snapshot.accounts[0].resetCredits?.availableCount, 2)
        XCTAssertEqual(snapshot.accounts[0].resetCredits?.resets.first?.expiresAt, Date(timeIntervalSince1970: 1_782_000_000))
        XCTAssertTrue(snapshot.accounts[0].isActive)
        XCTAssertEqual(snapshot.accounts[1].displayName, "Personal")
        XCTAssertEqual(snapshot.accounts[1].username, "Personal")
        XCTAssertEqual(snapshot.accounts[1].workspaceName, "Personal")
        XCTAssertFalse(snapshot.accounts[1].isActive)
        XCTAssertFalse(snapshot.securityNotes.joined(separator: " ").localizedCaseInsensitiveContains("token"))
    }

    private func checkCodexRegistryParsesMultipleWorkspacesForOneAccount() throws {
        let registry = """
        {
          "schema_version": 3,
          "active_account_key": "acct-business",
          "accounts": [
            {
              "account_key": "acct-business",
              "email": "person@example.com",
              "workspace_name": "Core Team",
              "workspace_id": "core-123456",
              "workspace_names": ["Fresh Invite"],
              "workspaces": [
                {"name": "Client Team", "id": "client-ab"},
                {"workspace_name": "Core Team", "workspace_id": "core-123456"}
              ],
              "invites": [
                {"organization_name": "Partner Space", "chatgpt_account_id": "partner-id"}
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try CodexUsageReader.parseRegistry(data: registry, now: Date(timeIntervalSince1970: 1_781_388_300))
        let account = try XCTUnwrap(snapshot.accounts.first)

        XCTAssertEqual(account.workspaceName, "Core Team")
        XCTAssertEqual(account.workspaceID, "core-123456")
        XCTAssertEqual(account.workspaces.count, 4)
        XCTAssertEqual(account.workspaceDisplayValues, [
            "Core Team · core-123456",
            "Fresh Invite",
            "Client Team · client-ab",
            "Partner Space · partner-id"
        ])
        XCTAssertEqual(account.workspaceLines(language: .english, limit: 3), [
            "Workspaces: Core Team · core-123456",
            "Fresh Invite",
            "Client Team · client-ab",
            "+1 more"
        ])
    }

    private func checkAccountsWithSameIdentityGroupForDisplayWithoutMergingWorkspaceRows() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        var core = testAccount(id: "person::core", name: "person@example.com", fiveHourUsed: 18, weeklyUsed: 51, now: now)
        core.workspaceName = "Core Team"
        core.workspaceID = "core-123456"
        core.workspaces = [UsageWorkspace(name: "Core Team", workspaceID: "core-123456")]
        core.isActive = true

        var client = testAccount(id: "person::client", name: "person@example.com", fiveHourUsed: 18, weeklyUsed: 51, now: now)
        client.workspaceName = "Client Team"
        client.workspaceID = "client-ab"
        client.workspaces = [UsageWorkspace(name: "Client Team", workspaceID: "client-ab")]

        let groups = [client, core].displayGroupsByIdentity(sortMode: .activeFirst)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.title, "person@example.com")
        XCTAssertEqual(groups.first?.accounts.map(\.id), ["person::core", "person::client"])
        XCTAssertEqual(groups.first?.accounts.map(\.workspaceDisplayValue), [
            "Core Team · core-123456",
            "Client Team · client-ab"
        ])
    }

    private func checkCodexRegistryFlagsAccountsThatNeedLoginAgain() throws {
        let registry = """
        {
          "schema_version": 3,
          "accounts": [
            {
              "account_key": "acct-401",
              "email": "locked@example.com",
              "plan": "401",
              "agentbar_auth_error": {"status_code": 401},
              "last_usage": {
                "plan_type": "401",
                "primary": {"used_percent": 401, "window_minutes": 300, "resets_at": 1781400000}
              }
            },
            {
              "account_key": "acct-reset",
              "email": "reset@example.com",
              "last_usage": {
                "primary": {"used_percent": 8, "window_minutes": 300}
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try CodexUsageReader.parseRegistry(data: registry, now: Date(timeIntervalSince1970: 1_781_388_300))

        XCTAssertEqual(snapshot.accounts.first { $0.id == "acct-401" }?.loginWarning, .forcedLogout)
        XCTAssertNil(snapshot.accounts.first { $0.id == "acct-401" }?.fiveHourWindow)
        XCTAssertEqual(snapshot.accounts.first { $0.id == "acct-reset" }?.loginWarning, .unreadableReset)
    }

    private func checkCodexReadClearsStale401AfterNewerAuthSnapshot() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try """
        {
          "schema_version": 3,
          "accounts": [
            {
              "account_key": "user-a::org",
              "email": "person@example.com",
              "plan": "team",
              "agentbar_auth_error": {"status_code": 401, "detected_at": 1000},
              "last_usage": {
                "plan_type": "team",
                "primary": {"used_percent": 8, "window_minutes": 300, "resets_at": 1781400000}
              }
            }
          ]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        let authFileKey = Data("user-a::org".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let authURL = accountDir.appending(path: "\(authFileKey).auth.json")
        try "{}".data(using: .utf8)!.write(to: authURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: authURL.path)

        let snapshot = CodexUsageReader(homeDirectory: temp).read()

        XCTAssertNil(snapshot.accounts.first?.loginWarning)
    }

    private func checkCodexSessionJsonlAggregatesTokenUsageAndRateLimits() throws {
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

    private func checkCodexSessionJsonlUsesTurnContextModelForCostBreakdown() throws {
        let jsonl = """
        {"type":"turn_context","payload":{"model":"openai/gpt-5.5-2026-06-01"}}
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":200000,"output_tokens":100000,"reasoning_output_tokens":0,"total_tokens":1100000}}}}
        {"type":"turn_context","payload":{"model":"gpt-5.4-mini"}}
        {"type":"event_msg","timestamp":"2026-06-13T22:07:12.184Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":0,"output_tokens":100000,"reasoning_output_tokens":0,"total_tokens":1100000}}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.points.map(\.model), ["gpt-5.5", "gpt-5.4-mini"])
        XCTAssertEqual(metrics.points.first?.estimatedCostUSD, Decimal(string: "7.1"))
        XCTAssertEqual(metrics.points.last?.estimatedCostUSD, Decimal(string: "0.45"))
    }

    private func checkCodexSessionJsonlParsesResetCreditsFromRateLimitEvents() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-13T22:06:23.246Z","payload":{"rate_limits":{"primary":{"used_percent":7,"window_minutes":300,"resets_at":1781406270}},"rate_limit_reset_credits":{"available_count":2,"resets":[{"expires_at":1782000000}]}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.latestResetCredits?.availableCount, 2)
        XCTAssertEqual(metrics.latestResetCredits?.resets.first?.expiresAt, Date(timeIntervalSince1970: 1_782_000_000))
    }

    private func checkCodexSessionJsonlCarriesSessionAndProjectMetadata() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-13T22:06:01.000Z","payload":{"type":"user_message","message":"# Files mentioned by the user:\\n\\n## My request for Codex:\\nFix high CPU usage in AgentBar\\n"}}
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","session_id":"session-1","payload":{"cwd":"/Users/terrytan/Desktop/Coding/AgentBar","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.points.first?.sessionID, "session-1")
        XCTAssertEqual(metrics.points.first?.sessionTitle, "Fix high CPU usage in AgentBar")
        XCTAssertEqual(metrics.points.first?.projectName, "AgentBar")
    }

    private func checkCodexSessionJsonlDerivesDailyUsageAcrossQuotaReset() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-14T02:30:00.000Z","payload":{"info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":10,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":100}},"rate_limits":{"primary":{"used_percent":90,"window_minutes":300,"resets_at":1781488800},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1781900000}}}}
        {"type":"event_msg","timestamp":"2026-06-14T02:45:00.000Z","payload":{"info":{"total_token_usage":{"input_tokens":130,"cached_input_tokens":15,"output_tokens":30,"reasoning_output_tokens":0,"total_tokens":160}},"rate_limits":{"primary":{"used_percent":96,"window_minutes":300,"resets_at":1781488800},"secondary":{"used_percent":41,"window_minutes":10080,"resets_at":1781900000}}}}
        {"type":"event_msg","timestamp":"2026-06-14T03:10:00.000Z","payload":{"info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":25}},"rate_limits":{"primary":{"used_percent":4,"window_minutes":300,"resets_at":1781506800},"secondary":{"used_percent":41,"window_minutes":10080,"resets_at":1781900000}}}}
        """.data(using: .utf8)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-14T04:00:00Z")!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)
        let summary = UsageStatistics.summarize(points: metrics.points, range: .today, now: now, calendar: calendar)
        let bar = try XCTUnwrap(summary.dailyBars.first)
        let tooltip = bar.tooltipText(language: .english)

        XCTAssertEqual(bar.codexTokens, 185)
        XCTAssertTrue(tooltip.contains("Codex: 185 Tokens"))
        XCTAssertFalse(tooltip.contains("285"))
    }

    private func checkCodexUsageAPISyncerUpdatesRegistryWithoutCodexAuthRuntime() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {
          "schema_version": 3,
          "active_account_key": "acct-a",
          "accounts": [
            {
              "account_key": "acct-a",
              "email": "person@example.com",
              "plan": "team",
              "last_usage": {
                "primary": {"used_percent": 90, "window_minutes": 300, "resets_at": 1781400000},
                "secondary": {"used_percent": 80, "window_minutes": 10080, "resets_at": 1781900000}
              }
            }
          ]
        }
        """.data(using: .utf8)!.write(to: registryURL)
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "secret-access-token",
            "account_id": "chatgpt-account-id"
          }
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-a.auth.json"))

        let requestRecorder = UsageAPIRequestRecorder()
        let syncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            now: { Date(timeIntervalSince1970: 1_781_388_300) },
            usageClient: { request, timeout in
                XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
                XCTAssertEqual(timeout, 5)
                requestRecorder.record(request)
                return CodexUsageAPIResponse(
                    statusCode: 200,
                    data: """
                    {
                      "plan_type": "business",
                      "rate_limit_reset_credits": {
                        "available_count": 2,
                        "resets": [{"expires_at": 1782000000}]
                      },
                      "rate_limit": {
                        "primary_window": {"used_percent": 8, "limit_window_seconds": 18000, "reset_at": 1781400000},
                        "secondary_window": {"used_percent": 55, "limit_window_seconds": 604800, "reset_at": 1781900000}
                      }
                    }
                    """.data(using: .utf8)!
                )
            }
        )

        XCTAssertEqual(syncer.refreshUsage(), .success)

        XCTAssertEqual(requestRecorder.authorization, "Bearer secret-access-token")
        XCTAssertEqual(requestRecorder.accountID, "chatgpt-account-id")
        let data = try Data(contentsOf: registryURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let accounts = try XCTUnwrap(json["accounts"] as? [[String: Any]])
        let account = try XCTUnwrap(accounts.first)
        let usage = try XCTUnwrap(account["last_usage"] as? [String: Any])
        let primary = try XCTUnwrap(usage["primary"] as? [String: Any])
        let secondary = try XCTUnwrap(usage["secondary"] as? [String: Any])
        XCTAssertEqual(primary["used_percent"] as? Double, 8)
        XCTAssertEqual(primary["window_minutes"] as? Int, 300)
        XCTAssertEqual(secondary["used_percent"] as? Double, 55)
        XCTAssertEqual(secondary["window_minutes"] as? Int, 10080)
        let resetCredits = try XCTUnwrap(usage["reset_credits"] as? [String: Any])
        XCTAssertEqual(resetCredits["available_count"] as? Int, 2)
        let resets = try XCTUnwrap(resetCredits["resets"] as? [[String: Any]])
        XCTAssertEqual(resets.first?["expires_at"] as? Double, 1_782_000_000)
        XCTAssertEqual(usage["plan_type"] as? String, "business")
        XCTAssertEqual(account["last_usage_at"] as? Double, 1_781_388_300)
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("secret-access-token") ?? true)
    }

    private func checkCodexUsageAPISyncerRefreshesOnlyActiveAccount() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-a","email":"active@example.com"},{"account_key":"acct-b","email":"other@example.com"}]}
        """.data(using: .utf8)!.write(to: registryURL)
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"active-token","account_id":"active-chatgpt-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-a.auth.json"))
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"other-token","account_id":"other-chatgpt-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-b.auth.json"))

        let requestRecorder = UsageAPIRequestRecorder()
        let syncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            usageClient: { request, _ in
                requestRecorder.record(request)
                return CodexUsageAPIResponse(
                    statusCode: 200,
                    data: #"{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1781400000}}}"#.data(using: .utf8)!
                )
            }
        )

        XCTAssertEqual(syncer.refreshUsage(), .success)
        XCTAssertEqual(requestRecorder.requestCount, 1)
        XCTAssertEqual(requestRecorder.accountID, "active-chatgpt-id")
        let accounts = try registryAccounts(from: registryURL)
        XCTAssertNotNil(accounts.first { $0["account_key"] as? String == "acct-a" }?["last_usage"])
        XCTAssertNil(accounts.first { $0["account_key"] as? String == "acct-b" }?["last_usage"])
        XCTAssertNil(accounts.first { $0["account_key"] as? String == "acct-b" }?["agentbar_auth_error"])
    }

    private func checkCodexUsageAPISyncerOptInFetchesDetailedResetExpiryDates() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-a","email":"person@example.com"}]}
        """.data(using: .utf8)!.write(to: registryURL)
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"secret-access-token","account_id":"chatgpt-account-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-a.auth.json"))

        let urlRecorder = UsageAPIURLRecorder()
        let syncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            usageClient: { request, _ in
                urlRecorder.record(request.url?.absoluteString ?? "")
                if request.url == CodexUsageAPISyncer.resetCreditsEndpoint {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "Codex Desktop")
                    return CodexUsageAPIResponse(
                        statusCode: 200,
                        data: """
                        {
                          "available_count": 2,
                          "credits": [
                            {"id":"a","status":"available","expires_at":"2026-07-12T18:38:00Z"},
                            {"id":"b","status":"redeemed","expires_at":"2026-07-13T18:38:00Z"},
                            {"id":"c","status":"available","expires_at":"2026-07-18T15:16:00Z"}
                          ]
                        }
                        """.data(using: .utf8)!
                    )
                }
                return CodexUsageAPIResponse(
                    statusCode: 200,
                    data: """
                    {"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1781400000}},"rate_limit_reset_credits":{"available_count":2}}
                    """.data(using: .utf8)!
                )
            },
            detailedResetCreditsEnabled: true
        )

        XCTAssertEqual(syncer.refreshUsage(), .success)
        XCTAssertEqual(urlRecorder.urls, [
            "https://chatgpt.com/backend-api/wham/usage",
            "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
        ])
        let usage = try XCTUnwrap(registryAccount(from: registryURL)["last_usage"] as? [String: Any])
        let resetCredits = try XCTUnwrap(usage["reset_credits"] as? [String: Any])
        XCTAssertEqual(resetCredits["available_count"] as? Int, 2)
        let resets = try XCTUnwrap(resetCredits["resets"] as? [[String: Any]])
        XCTAssertEqual(resets.count, 2)
        XCTAssertEqual(resets.map { $0["expires_at"] as? Double }, [1_783_881_480, 1_784_387_760])
    }

    private func checkCodexUsageAPISyncerPersists401AndClearsItAfterSuccess() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-a","email":"person@example.com"}]}
        """.data(using: .utf8)!.write(to: registryURL)
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"secret-access-token","account_id":"chatgpt-account-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-a.auth.json"))

        let unauthorizedResponse = CodexUsageAPIResponse(statusCode: 401, data: Data())
        let unauthorizedSyncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            now: { Date(timeIntervalSince1970: 1_781_388_300) },
            usageClient: { _, _ in unauthorizedResponse }
        )

        XCTAssertEqual(unauthorizedSyncer.refreshUsage(), .failed("HTTP 401"))
        var account = try registryAccount(from: registryURL)
        XCTAssertEqual((account["agentbar_auth_error"] as? [String: Any])?["status_code"] as? Int, 401)

        let successResponse = CodexUsageAPIResponse(
            statusCode: 200,
            data: """
            {"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1781400000}}}
            """.data(using: .utf8)!
        )
        let successSyncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            now: { Date(timeIntervalSince1970: 1_781_388_400) },
            usageClient: { _, _ in successResponse }
        )

        XCTAssertEqual(successSyncer.refreshUsage(), .success)
        account = try registryAccount(from: registryURL)
        XCTAssertNil(account["agentbar_auth_error"])
    }

    private func checkCodexUsageAPISyncerUsesNewerActiveAuthForActiveAccount() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-a","email":"person@example.com","agentbar_auth_error":{"status_code":401,"detected_at":1000}}]}
        """.data(using: .utf8)!.write(to: registryURL)
        let staleSnapshotURL = accountDir.appending(path: "acct-a.auth.json")
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"old-token","account_id":"chatgpt-account-id"}}
        """.data(using: .utf8)!.write(to: staleSnapshotURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: staleSnapshotURL.path)
        let activeAuthURL = temp.appending(path: ".codex/auth.json")
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"new-token","account_id":"chatgpt-account-id"}}
        """.data(using: .utf8)!.write(to: activeAuthURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: activeAuthURL.path)

        let syncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            usageClient: { request, _ in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
                return CodexUsageAPIResponse(
                    statusCode: 200,
                    data: #"{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1781400000}}}"#.data(using: .utf8)!
                )
            }
        )

        XCTAssertEqual(syncer.refreshUsage(), .success)
        XCTAssertTrue((try String(contentsOf: staleSnapshotURL)).contains("new-token"))
        XCTAssertNil(try registryAccount(from: registryURL)["agentbar_auth_error"])
    }

    private func checkCodexRecoveryLoginCommandSavesActiveAuthToSelectedSnapshot() {
        let command = AccountLoginLauncher.codexRecoveryLoginCommand(accountID: "user-a::org")

        XCTAssertTrue(command.hasPrefix("codex login &&"))
        XCTAssertTrue(command.contains(#"cp "$HOME/.codex/auth.json" "$HOME/.codex/accounts/dXNlci1hOjpvcmc.auth.json""#))
    }

    private func checkCodexAccountStorageCentralizesRegistryAuthAndRecoveryPaths() {
        let home = URL(fileURLWithPath: "/tmp/agentbar-codex-home")
        let storage = CodexAccountStorage(homeDirectory: home)

        XCTAssertEqual(storage.registryURL.path, "/tmp/agentbar-codex-home/.codex/accounts/registry.json")
        XCTAssertEqual(storage.activeAuthURL.path, "/tmp/agentbar-codex-home/.codex/auth.json")
        XCTAssertEqual(storage.accountAuthURL(for: "user-a::org").path, "/tmp/agentbar-codex-home/.codex/accounts/dXNlci1hOjpvcmc.auth.json")
        XCTAssertEqual(storage.accountAuthURL(for: "plain-account").path, "/tmp/agentbar-codex-home/.codex/accounts/plain-account.auth.json")
        XCTAssertTrue(storage.recoveryLoginCommand(accountID: "user-a::org").contains(#"cp "$HOME/.codex/auth.json" "$HOME/.codex/accounts/dXNlci1hOjpvcmc.auth.json""#))
    }

    @MainActor
    private func checkRefreshingAfterInitialLoadDoesNotReturnAccountUIToLoadingState() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(
            settings: SettingsStore(defaults: defaults),
            codexUsageSynchronizer: { .success }
        )
        store.applyTestData(accounts: [testAccount(id: "active", name: "active@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: Date())])

        store.refresh(force: true)

        XCTAssertTrue(store.hasLoadedAccountInformation)
        XCTAssertFalse(store.isLoadingAccountInformation)
    }

    @MainActor
    private func checkRefreshSyncsCodexUsageAPIBeforeReadingUsage() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let expectation = expectation(description: "refresh completed")
        let recorder = RefreshOrderRecorder()
        let now = Date()
        let activeAccount = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 8, weeklyUsed: 55, now: now)
        let store = UsageStore(
            settings: settings,
            codexUsageSynchronizer: {
                recorder.record("sync")
                return .success
            },
            codexUsageReader: {
                XCTAssertEqual(recorder.events, ["sync"])
                recorder.record("codex-read")
                return UsageSnapshot(
                    service: .codex,
                    status: .live,
                    accounts: [
                        activeAccount
                    ],
                    points: [],
                    securityNotes: [],
                    refreshedAt: now,
                    pricingFingerprint: Pricing.fingerprint
                )
            },
            claudeUsageReader: {
                XCTAssertEqual(recorder.events, ["sync", "codex-read"])
                expectation.fulfill()
                return .empty(service: .claudeCode, status: .unavailable, note: "test")
            }
        )

        store.refresh(force: true)

        wait(for: [expectation], timeout: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(store.menuBarTitle, "5H 92%  WK 45%")
    }

    private func checkUsageRefreshOrchestratorSyncsBeforeReadersAndMergesSnapshots() {
        let recorder = RefreshOrderRecorder()
        let now = Date()
        let codexAccount = testAccount(id: "codex", name: "codex@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: now)
        let claudePoint = UsagePoint(
            service: .claudeCode,
            model: "claude-opus",
            date: now,
            tokens: TokenTotals(input: 10, cachedInput: 0, output: 15, reasoningOutput: 0, total: 25),
            estimatedCostUSD: nil
        )
        let orchestrator = UsageRefreshOrchestrator(
            codexUsageSource: { detailedResetCreditsEnabled in
                XCTAssertFalse(detailedResetCreditsEnabled)
                recorder.record("codex-source")
                return UsageSnapshot(
                    service: .codex,
                    status: .live,
                    accounts: [codexAccount],
                    points: [],
                    securityNotes: ["source note"],
                    refreshedAt: now,
                    pricingFingerprint: Pricing.fingerprint
                )
            },
            claudeUsageReader: {
                XCTAssertEqual(recorder.events, ["codex-source"])
                recorder.record("claude-read")
                return UsageSnapshot(
                    service: .claudeCode,
                    status: .live,
                    accounts: [],
                    points: [claudePoint],
                    securityNotes: [],
                    refreshedAt: now,
                    pricingFingerprint: Pricing.fingerprint
                )
            }
        )

        let result = orchestrator.refresh(detailedResetCreditsEnabled: false)

        XCTAssertEqual(recorder.events, ["codex-source", "claude-read"])
        XCTAssertEqual(result.snapshots[.codex]?.securityNotes, ["source note"])
        XCTAssertEqual(result.snapshots[.claudeCode]?.points, [claudePoint])
        XCTAssertEqual(result.accounts.map(\.id), ["codex"])
        XCTAssertEqual(result.points, [claudePoint])
    }

    private func checkCodexUsageSourceSyncsBeforeReadAndAppendsSyncNote() {
        let recorder = RefreshOrderRecorder()
        let now = Date()
        let source = CodexUsageSource(
            codexUsageSynchronizer: {
                recorder.record("normal-sync")
                return .success
            },
            codexDetailedResetCreditsSynchronizer: {
                recorder.record("detailed-sync")
                return .failed("expired token")
            },
            codexUsageReader: {
                XCTAssertEqual(recorder.events, ["detailed-sync"])
                recorder.record("codex-read")
                return UsageSnapshot(
                    service: .codex,
                    status: .live,
                    accounts: [],
                    points: [],
                    securityNotes: ["local note"],
                    refreshedAt: now,
                    pricingFingerprint: Pricing.fingerprint
                )
            }
        )

        let snapshot = source.read(detailedResetCreditsEnabled: true)

        XCTAssertEqual(recorder.events, ["detailed-sync", "codex-read"])
        XCTAssertEqual(snapshot.securityNotes, [
            "local note",
            "Codex usage API sync failed: expired token; using local registry and session cache."
        ])
    }

    @MainActor
    private func checkDarkThemeSettingPersistsAndToneColorCopyIsLocalized() {
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
    }

    @MainActor
    private func checkPopoverHeightPreferenceIsClampedWhenLoadedAndSaved() {
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

    private func checkCodexReadPrefersRegistryUsageOverLocalSessionRateLimits() throws {
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

        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 90)
        XCTAssertEqual(active.weeklyWindow?.usedPercent, 80)
        XCTAssertEqual(inactive.fiveHourWindow?.usedPercent, 40)
        XCTAssertEqual(inactive.weeklyWindow?.usedPercent, 30)
    }

    private func checkCodexReadUsesNewestRateLimitEventAcrossSessionFiles() throws {
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

    private func checkCodexSessionMetricsCacheInvalidatesWhenFileChanges() throws {
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

    private func checkCodexSessionMetricsCacheDropsDeletedFiles() throws {
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

    private func checkCodexReadKeepsSwitchedAccountWindowsWhenLatestSessionPredatesActivation() throws {
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

    private func checkSessionRateLimitsWithoutParsableTimestampDoNotOverrideActiveAccountWindows() throws {
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
          "active_account_activated_at_ms": 1781400000000,
          "accounts": [
            {
              "account_key": "active",
              "email": "active@example.com",
              "last_usage": {
                "primary": {"used_percent": 25, "window_minutes": 300, "resets_at": 1781410000},
                "secondary": {"used_percent": 35, "window_minutes": 10080, "resets_at": 1781910000}
              }
            }
          ]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","payload":{"rate_limits":{"primary":{"used_percent":99,"window_minutes":300,"resets_at":1781420000},"secondary":{"used_percent":98,"window_minutes":10080,"resets_at":1781920000}}}}
        {"type":"event_msg","timestamp":"not-a-date","payload":{"rate_limits":{"primary":{"used_percent":97,"window_minutes":300,"resets_at":1781420000},"secondary":{"used_percent":96,"window_minutes":10080,"resets_at":1781920000}}}}
        """.data(using: .utf8)!.write(to: sessionDir.appending(path: "forged.jsonl"))

        let snapshot = CodexUsageReader(homeDirectory: temp).read()
        let active = try XCTUnwrap(snapshot.accounts.first)

        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 25)
        XCTAssertEqual(active.weeklyWindow?.usedPercent, 35)
    }

    private func checkOversizedSessionFilesAreSkipped() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/06")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"schema_version":3,"active_account_key":"active","accounts":[{"account_key":"active","email":"active@example.com"}]}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try Data(count: CodexUsageReader.maximumSessionFileBytes + 1)
            .write(to: sessionDir.appending(path: "oversized.jsonl"))

        let snapshot = CodexUsageReader(homeDirectory: temp).read()

        XCTAssertEqual(snapshot.points.count, 0)
        XCTAssertEqual(snapshot.accounts.first?.tokens.total, 0)
    }

    private func checkOpenAIModelPricingCalculatesPointCost() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","payload":{"info":{"model":"gpt-5.1","last_token_usage":{"input_tokens":1000000,"cached_input_tokens":100000,"output_tokens":100000,"reasoning_output_tokens":0,"total_tokens":1100000}}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.points.count, 1)
        XCTAssertEqual(metrics.points[0].estimatedCostUSD ?? 0, Decimal(string: "2.1375"))
    }

    private func checkPricingNormalizesProviderAndDateSuffixes() {
        XCTAssertEqual(Pricing.normalize(model: "openai/GPT-5.4@20260131"), "gpt-5.4")
        XCTAssertEqual(Pricing.normalize(model: "claude-sonnet-4-5-20260229"), "claude-sonnet-4-5")
        XCTAssertEqual(Pricing.normalize(model: "claude-opus-4-7-2026-02-29"), "claude-opus-4-7")
    }

    private func checkPricingUsesDecimalAndUnknownModelsCostZeroButKeepTokens() {
        let unknown = Pricing.cost(model: "codex-auto-review", input: 99_000_000, output: 1_000_000, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(unknown, 0)

        let known = Pricing.cost(model: "openai/gpt-5.4@20260131", input: 1_000_000, output: 100_000, cacheRead: 100_000, cacheCreation: 0)
        XCTAssertEqual(known, Decimal(string: "4.025"))
    }

    private func checkPricingFingerprintIsStableSHA256AndIncludedInSummary() {
        XCTAssertEqual(Pricing.fingerprint.count, 64)
        XCTAssertTrue(Pricing.fingerprint.allSatisfy { $0.isHexDigit })

        let summary = UsageStatistics.summarize(points: [], range: .all)
        XCTAssertEqual(summary.pricingFingerprint, Pricing.fingerprint)
    }

    @MainActor
    private func checkMenuBarDefaultsToActiveAccountQuotaWindows() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let store = UsageStore(settings: settings, codexUsageSynchronizer: { .success })
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
    private func checkPopoverHeaderShowsActiveAccountFiveHourAndWeeklyRemaining() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let store = UsageStore(settings: settings, codexUsageSynchronizer: { .success })
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
    private func checkMenuBarDisplayModeMigratesExistingInstallToActiveAccountWindows() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MenuBarDisplayMode.lowestRemaining.rawValue, forKey: "menuBarDisplayMode")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.menuBarDisplayMode, .activeAccountWindows)
    }

    @MainActor
    private func checkBudgetSettingsPersistAndWarnInMenuBarTitle() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.dailyTokenBudget = 1_000
        settings.weeklyTokenBudget = 7_000
        settings.dailyCostBudgetUSD = 2.5
        settings.weeklyCostBudgetUSD = 12.5

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.dailyTokenBudget, 1_000)
        XCTAssertEqual(reloaded.weeklyTokenBudget, 7_000)
        XCTAssertEqual(reloaded.dailyCostBudgetUSD, 2.5)
        XCTAssertEqual(reloaded.weeklyCostBudgetUSD, 12.5)

        let store = UsageStore(settings: reloaded, codexUsageSynchronizer: { .success })
        store.applyTestData(
            accounts: [testAccount(id: "active", name: "active@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: Date())],
            points: [
                UsagePoint(
                    service: .codex,
                    model: "codex-local",
                    date: Date(),
                    tokens: TokenTotals(input: 600, cachedInput: 0, output: 400, reasoningOutput: 0, total: 1_000),
                    estimatedCostUSD: Decimal(string: "2.75")
                )
            ]
        )

        XCTAssertTrue(store.menuBarTitle.hasPrefix("! "))
    }

    @MainActor
    private func checkRapidUsageAlertWarnsInMenuBarTitle() {
        let now = Date()
        let recentPointDate = max(now.addingTimeInterval(-60), Calendar.current.startOfDay(for: now))
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(settings: SettingsStore(defaults: defaults), codexUsageSynchronizer: { .success })
        store.applyTestData(
            accounts: [testAccount(id: "active", name: "active@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: now)],
            points: [
                UsagePoint(
                    service: .codex,
                    model: "codex-local",
                    date: recentPointDate,
                    tokens: TokenTotals(input: 3_000, cachedInput: 0, output: 3_000, reasoningOutput: 0, total: 6_000),
                    estimatedCostUSD: nil
                ),
                UsagePoint(
                    service: .codex,
                    model: "codex-local",
                    date: now,
                    tokens: TokenTotals(input: 2_000, cachedInput: 0, output: 2_000, reasoningOutput: 0, total: 4_000),
                    estimatedCostUSD: nil
                )
            ]
        )

        XCTAssertTrue(store.menuBarTitle.hasPrefix("! "))
    }

    private func checkStatisticsBucketsAggregateExpectedRanges() {
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
        XCTAssertEqual(today.dailyBars.first?.codexCostUSD, Decimal(string: "0.001"))
        XCTAssertEqual(sevenDays.dailyBars.map(\.codexCostUSD).reduce(Decimal(0), +), Decimal(string: "0.003"))
    }

    private func checkPeriodChangeComparesSelectedRangeAgainstPreviousPeriod() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-13T22:00:00Z")!
        let points = [
            UsagePoint(service: .codex, model: "codex-local", date: now, tokens: TokenTotals(input: 120, cachedInput: 0, output: 30, reasoningOutput: 0, total: 150), estimatedCostUSD: Decimal(string: "3.00")),
            UsagePoint(service: .codex, model: "codex-local", date: calendar.date(byAdding: .day, value: -1, to: now)!, tokens: TokenTotals(input: 80, cachedInput: 0, output: 20, reasoningOutput: 0, total: 100), estimatedCostUSD: Decimal(string: "2.00")),
            UsagePoint(service: .codex, model: "codex-local", date: calendar.date(byAdding: .day, value: -2, to: now)!, tokens: TokenTotals(input: 800, cachedInput: 0, output: 200, reasoningOutput: 0, total: 1_000), estimatedCostUSD: Decimal(string: "10.00"))
        ]

        let change = UsageStatistics.periodChange(points: points, range: .today, now: now, calendar: calendar)

        XCTAssertEqual(try XCTUnwrap(change.tokenPercent), 50, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(change.costPercent), 50, accuracy: 0.001)
    }

    private func checkPeriodChangeHasNoPercentWithoutComparableBaseline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-13T22:00:00Z")!
        let points = [
            UsagePoint(service: .codex, model: "codex-local", date: now, tokens: TokenTotals(input: 120, cachedInput: 0, output: 30, reasoningOutput: 0, total: 150), estimatedCostUSD: Decimal(string: "3.00"))
        ]

        let todayChange = UsageStatistics.periodChange(points: points, range: .today, now: now, calendar: calendar)
        let allChange = UsageStatistics.periodChange(points: points, range: .all, now: now, calendar: calendar)

        XCTAssertNil(todayChange.tokenPercent)
        XCTAssertNil(todayChange.costPercent)
        XCTAssertNil(allChange.tokenPercent)
        XCTAssertNil(allChange.costPercent)
    }

    private func checkUsageRangeIntervalsDriveStatisticsAndAuditFiltering() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-13T22:00:00Z")!
        let currentStart = calendar.date(byAdding: .day, value: -7, to: now)!
        let previousStart = currentStart.addingTimeInterval(-7 * 24 * 60 * 60)
        let points = [
            UsagePoint(service: .codex, model: "codex-local", date: now, tokens: TokenTotals(input: 60, cachedInput: 0, output: 40, reasoningOutput: 0, total: 100), estimatedCostUSD: nil),
            UsagePoint(service: .codex, model: "codex-local", date: currentStart.addingTimeInterval(60), tokens: TokenTotals(input: 30, cachedInput: 0, output: 20, reasoningOutput: 0, total: 50), estimatedCostUSD: nil),
            UsagePoint(service: .codex, model: "codex-local", date: previousStart.addingTimeInterval(60), tokens: TokenTotals(input: 10, cachedInput: 0, output: 10, reasoningOutput: 0, total: 20), estimatedCostUSD: nil)
        ]

        let current = try XCTUnwrap(UsageRange.last7Days.dateInterval(now: now, calendar: calendar))
        let previous = try XCTUnwrap(UsageRange.last7Days.previousDateInterval(currentInterval: current, calendar: calendar))

        XCTAssertEqual(points.filter { current.contains($0.date) }.map(\.tokens.total).reduce(0, +), 150)
        XCTAssertEqual(points.filter { previous.contains($0.date) }.map(\.tokens.total).reduce(0, +), 20)
        XCTAssertEqual(UsageStatistics.summarize(points: points, range: .last7Days, now: now, calendar: calendar).totalTokens, 150)
        XCTAssertEqual(UsageAuditReporter.filteredPoints(points: points, range: .last7Days, now: now, calendar: calendar).map(\.tokens.total).reduce(0, +), 150)
        XCTAssertEqual(UsageAuditReporter.rangeComparison(points: points, range: .last7Days, now: now, calendar: calendar)?.previousTokens, 20)
    }

    private func checkChangePercentFormattingShowsDirectionAndMissingBaseline() {
        XCTAssertEqual(DisplayFormatters.changePercentString(50), "↑ 50.0%")
        XCTAssertEqual(DisplayFormatters.changePercentString(-25.26), "↓ 25.3%")
        XCTAssertEqual(DisplayFormatters.changePercentString(0), "0.0%")
        XCTAssertEqual(DisplayFormatters.changePercentString(nil), "--")
    }

    private func checkAccountSortingUsesFiveHourThenWeeklyPressure() {
        let now = Date()
        let accounts = [
            testAccount(id: "a", name: "a@example.com", fiveHourUsed: 1, weeklyUsed: 10, now: now),
            testAccount(id: "b", name: "b@example.com", fiveHourUsed: 100, weeklyUsed: 1, now: now),
            testAccount(id: "c", name: "c@example.com", fiveHourUsed: 1, weeklyUsed: 40, now: now)
        ]

        let sorted = accounts.sorted(using: .quotaPressure)

        XCTAssertEqual(sorted.map(\.id), ["b", "c", "a"])
    }

    private func checkAccountSortingPrioritizesResetCreditsAfterActiveAccount() {
        let now = Date()
        let accounts = [
            testAccount(id: "more-quota", name: "more@example.com", fiveHourUsed: 1, weeklyUsed: 10, now: now),
            testAccount(id: "reset-credit", name: "reset@example.com", fiveHourUsed: 45, weeklyUsed: 20, now: now, resetCredits: 1),
            testAccount(id: "constrained", name: "constrained@example.com", fiveHourUsed: 99, weeklyUsed: 99, now: now)
        ]

        let sorted = accounts.sorted(using: .quotaPressure)

        XCTAssertEqual(sorted.map(\.id), ["reset-credit", "constrained", "more-quota"])
    }

    private func checkAccountSortingAlwaysKeepsActiveAccountOnTop() {
        let now = Date()
        var active = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 1, weeklyUsed: 1, now: now)
        active.isActive = true
        let constrained = testAccount(id: "constrained", name: "constrained@example.com", fiveHourUsed: 100, weeklyUsed: 100, now: now)

        let sorted = [constrained, active].sorted(using: .quotaPressure)

        XCTAssertEqual(sorted.map(\.id), ["active", "constrained"])
    }

    private func checkEnglishCompactTokenFormattingUsesEnglishUnits() {
        XCTAssertEqual(DisplayFormatters.compactTokenString(63_229_600, language: .english), "63.2296 mil")
        XCTAssertEqual(DisplayFormatters.compactTokenString(6_322_960_000, language: .english), "6.3230 bil")
    }

    private func checkDailyUsageBarTooltipIncludesDateAndUsageDetails() {
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

    private func checkAccountMetadataShowsResetActivityAndAccountType() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let account = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 1, weeklyUsed: 8, now: now)

        XCTAssertTrue(account.accountTypeLine(language: .english).contains("Account type: TEAM"))
        XCTAssertTrue(account.lastActivityLine(language: .english).contains("Last activity:"))
        XCTAssertTrue(account.fiveHourWindow?.resetLine(language: .english).contains("Reset:") == true)
    }

    private func checkCodexAccountSwitcherCopiesSnapshotToActiveAuthAndTracksPrevious() throws {
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

    private func checkCodexAccountSwitcherRestoresAuthWhenRegistryWriteFails() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registry = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-a","email":"a@example.com"},{"account_key":"acct-b","email":"b@example.com"}]}
        """.data(using: .utf8)!.write(to: registry)
        let activeAuth = temp.appending(path: ".codex/auth.json")
        try "old active auth".data(using: .utf8)!.write(to: activeAuth)
        try "selected account auth".data(using: .utf8)!.write(to: accountDir.appending(path: "acct-b.auth.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: accountDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: accountDir.path)
            try? FileManager.default.removeItem(at: temp)
        }

        XCTAssertThrowsError(try CodexAccountSwitcher(homeDirectory: temp).switchActiveAccount(accountID: "acct-b"))
        XCTAssertEqual(try String(contentsOf: activeAuth, encoding: .utf8), "old active auth")
    }

    private func testAccount(
        id: String,
        name: String,
        fiveHourUsed: Double,
        weeklyUsed: Double,
        now: Date,
        resetCredits: Int = 0
    ) -> UsageAccount {
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
            resetCredits: resetCredits > 0 ? UsageResetCredits(availableCount: resetCredits) : nil,
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: now,
            isActive: false
        )
    }

    private func registryAccount(from url: URL) throws -> [String: Any] {
        try XCTUnwrap(registryAccounts(from: url).first)
    }

    private func registryAccounts(from url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["accounts"] as? [[String: Any]])
    }

    private final class RefreshOrderRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedEvents: [String] = []

        var events: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedEvents
        }

        func record(_ event: String) {
            lock.lock()
            recordedEvents.append(event)
            lock.unlock()
        }
    }

    private final class UsageAPIRequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        private var count = 0

        var requestCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        var authorization: String? {
            lock.lock()
            defer { lock.unlock() }
            return request?.value(forHTTPHeaderField: "Authorization")
        }

        var accountID: String? {
            lock.lock()
            defer { lock.unlock() }
            return request?.value(forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        func record(_ request: URLRequest) {
            lock.lock()
            self.request = request
            count += 1
            lock.unlock()
        }
    }

    private final class UsageAPIURLRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedURLs: [String] = []

        var urls: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedURLs
        }

        func record(_ url: String) {
            lock.lock()
            recordedURLs.append(url)
            lock.unlock()
        }
    }
}
