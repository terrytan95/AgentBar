import SwiftUI
import XCTest
@testable import AgentBar

final class UsageParsingTests: XCTestCase {

    @MainActor
    func testUsageParsingCoverage() async throws {
        try checkCodexRegistryParsesMultipleAccountsWithoutSecrets()
        try checkCodexRegistryDetectsWeeklyOnlyLimit()
        try checkCodexRegistryParsesMultipleWorkspacesForOneAccount()
        try checkCodexRegistrySharesWorkspaceNamesAcrossAccountRecords()
        checkAccountsWithSameIdentityGroupForDisplayWithoutMergingWorkspaceRows()
        try checkCodexRegistryFlagsAccountsThatNeedLoginAgain()
        try checkCodexRegistryTreatsTokenBacked401AsQuotaUnavailable()
        try checkCodexReadClearsStale401AfterNewerAuthSnapshot()
        try checkCodexReadUsesActiveAuthAccountWhenRegistryActiveIsStale()
        try checkCodexReadUsesAuthEmailToDisambiguateDuplicateWorkspaceIDs()
        try checkExpiredQuotaWindowsRestoreLocallyWithoutRefreshingUsage()
        try checkCodexSessionJsonlAggregatesTokenUsageAndRateLimits()
        try checkCodexSessionJsonlUsesTurnContextModelForCostBreakdown()
        try checkCodexSessionJsonlParsesResetCreditsFromRateLimitEvents()
        try checkCodexSessionJsonlCarriesSessionAndProjectMetadata()
        try checkCodexSessionJsonlBuildsTaskLifecycle()
        try checkCodexSessionJsonlDerivesDailyUsageAcrossQuotaReset()
        try await checkCodexUsageAPISyncerUpdatesRegistryWithoutCodexAuthRuntime()
        try await checkCodexUsageAPISyncerRefreshesInactiveAccountsHourly()
        try await checkCodexUsageAPISyncerAlwaysFetchesDetailedResetExpiryDates()
        try await checkCodexUsageAPISyncerPersists401AndClearsItAfterSuccess()
        try await checkCodexUsageAPISyncerUsesNewerActiveAuthForActiveAccount()
        try await checkCodexUsageAPISyncerRefreshesActiveAuthAccountWhenRegistryActiveIsStale()
        try await checkCodexUsageAPISyncerUsesAuthEmailToDisambiguateDuplicateWorkspaceIDs()
        checkCodexRecoveryLoginCommandSnapshotsAuthAfterLogin()
        try checkCodexAccessTokenUpdaterMarksTokenBackedSnapshot()
        checkCodexAccountStorageCentralizesRegistryAuthAndRecoveryPaths()
        try checkCodexAccountStorageParsesAccessTokenExpiration()
        try checkCodexReadUsesPerAccountAccessTokenExpirations()
        checkRefreshingAfterInitialLoadDoesNotReturnAccountUIToLoadingState()
        await checkUsageStoreReconcilesAccessTokenExpiryReminders()
        await checkRefreshSyncsCodexUsageAPIBeforeReadingUsage()
        checkDarkThemeSettingPersistsAndToneColorCopyIsLocalized()
        checkCodexSidebarQuotaOverlaySettingPersists()
        checkPopoverHeightPreferenceIsClampedWhenLoadedAndSaved()
        try checkCodexReadPrefersRegistryUsageOverLocalSessionRateLimits()
        try checkCodexReadDoesNotRestoreRemovedFiveHourLimitFromSessions()
        try checkCodexReadUsesNewestRateLimitEventAcrossSessionFiles()
        try checkCodexReadDoesNotInventLastActivityForAccountsMissingUsageTimestamp()
        try checkCodexSessionMetricsCacheInvalidatesWhenFileChanges()
        try checkCodexSessionMetricsCacheDropsDeletedFiles()
        try checkForkedSessionHistoryIsDeduplicated()
        try checkCodexReadKeepsSwitchedAccountWindowsWhenLatestSessionPredatesActivation()
        try checkSessionRateLimitsWithoutParsableTimestampDoNotOverrideActiveAccountWindows()
        try checkOversizedSessionFilesAreSkipped()
        try checkSessionFileCapSkipsAreReported()
        try checkCodexReadWarnsWhenSessionAccessIsDenied()
        try checkOpenAIModelPricingCalculatesPointCost()
        try checkGPT56BedrockPricingCalculatesPointCost()
        checkPricingNormalizesProviderAndDateSuffixes()
        checkPricingUsesDecimalAndUnknownModelsCostZeroButKeepTokens()
        checkPricingFingerprintIsStableSHA256AndIncludedInSummary()
        checkMenuBarDefaultsToActiveQuotaWithoutWarningMark()
        checkPopoverHeaderShowsActiveAccountFiveHourAndWeeklyRemaining()
        checkMenuBarDisplayModeMigratesExistingInstallToActiveAccountWindows()
        checkBudgetSettingsPersist()
        checkQuotaResetNotificationsDetectWindowRefreshes()
        checkTaskCompletionNotificationsDetectNewlyFinishedTasks()
        checkAccessTokenExpiryNotificationSettingPersists()
        checkAccessTokenExpiryReminderPlanning()
        checkQuotaCapacityHistoryEstimatesFromPercentAndTokenDelta()
        checkQuotaCapacityHistoryDoesNotEstimateAcrossAccountSwitches()
        checkStatisticsBucketsAggregateExpectedRanges()
        checkTodayAndYesterdayChartBarsUseHourlyBuckets()
        checkYearActivityBarsFillLast365Days()
        checkPeriodChangeComparesSelectedRangeAgainstPreviousPeriod()
        checkPeriodChangeHasNoPercentWithoutComparableBaseline()
        checkUsageStoreStatisticsCachesInvalidateWhenInputsChange()
        try checkUsageRangeIntervalsDriveStatisticsAndAuditFiltering()
        checkUsageRangeChartTitlesMatchSelectedInterval()
        checkChangePercentFormattingShowsDirectionAndMissingBaseline()
        checkCostFormattingUsesTwoDecimals()
        checkAccountSortingUsesFiveHourThenWeeklyPressure()
        checkAccountSortingPrioritizesResetCreditsAfterActiveAccount()
        checkAccountSortingAlwaysKeepsActiveAccountOnTop()
        checkAccountDataDisplayScopesUsagePoints()
        checkEnglishCompactTokenFormattingUsesEnglishUnits()
        checkDailyUsageBarTooltipIncludesDateAndUsageDetails()
        checkAccountMetadataShowsResetActivityAndAccountType()
        checkExpiredResetCreditUsesExpiredLabel()
        try checkCodexAccountSwitcherCopiesSnapshotToActiveAuthAndTracksPrevious()
        try checkCodexAccountSwitcherRejectsMismatchedSnapshot()
        try checkCodexAccountSwitcherRestoresAuthWhenRegistryWriteFails()
    }

    func testCodexDataSourceWarnsWhenAccessIsDenied() throws {
        try checkCodexReadWarnsWhenSessionAccessIsDenied()
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

    private func checkCodexRegistryDetectsWeeklyOnlyLimit() throws {
        let registry = """
        {
          "schema_version": 3,
          "active_account_key": "acct-weekly-only",
          "accounts": [
            {
              "account_key": "acct-weekly-only",
              "last_usage_at": 1783934177,
              "last_usage": {
                "primary": {"used_percent": 5, "window_minutes": 10080, "resets_at": 1784538977}
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let account = try XCTUnwrap(CodexUsageReader.parseRegistry(data: registry, now: Date()).accounts.first)

        XCTAssertNil(account.fiveHourWindow)
        XCTAssertEqual(account.weeklyWindow?.usedPercent, 5)
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

    private func checkCodexRegistrySharesWorkspaceNamesAcrossAccountRecords() throws {
        let registry = """
        {
          "schema_version": 3,
          "accounts": [
            {
              "account_key": "person-a::workspace-a",
              "email": "person-a@example.com",
              "account_name": "Design Team",
              "chatgpt_account_id": "workspace-a"
            },
            {
              "account_key": "person-b::workspace-a",
              "email": "person-b@example.com"
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try CodexUsageReader.parseRegistry(data: registry, now: Date(timeIntervalSince1970: 1_781_388_300))
        let account = try XCTUnwrap(snapshot.accounts.last)

        XCTAssertEqual(account.workspaceDisplayValue, "Design Team · workspace-a")
        XCTAssertEqual(account.workspaceLine(language: .english), "Workspace: Design Team · workspace-a")
    }

    private func checkExpiredQuotaWindowsRestoreLocallyWithoutRefreshingUsage() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let registry = """
        {
          "schema_version": 3,
          "active_account_key": "acct-a",
          "accounts": [
            {
              "account_key": "acct-a",
              "email": "person@example.com",
              "last_usage": {
                "primary": {"used_percent": 88, "window_minutes": 300, "resets_at": 1781388000},
                "secondary": {"used_percent": 62, "window_minutes": 10080, "resets_at": 1781388100}
              }
            }
          ]
        }
        """.data(using: .utf8)!
        try registry.write(to: accountDir.appending(path: "registry.json"))

        let account = try XCTUnwrap(codexReader(homeDirectory: temp, now: now).read().accounts.first)

        XCTAssertEqual(account.fiveHourWindow?.remainingPercent, 100)
        XCTAssertEqual(account.weeklyWindow?.remainingPercent, 100)
        XCTAssertNil(account.fiveHourWindow?.resetsAt)
        XCTAssertNil(account.weeklyWindow?.resetsAt)
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

    private func checkCodexRegistryTreatsTokenBacked401AsQuotaUnavailable() throws {
        let registry = """
        {
          "schema_version": 3,
          "accounts": [
            {
              "account_key": "acct-token",
              "email": "token@example.com",
              "agentbar_token_backed": true,
              "agentbar_auth_error": {"status_code": 401},
              "last_usage": {
                "plan_type": "401",
                "primary": {"used_percent": 401, "window_minutes": 300, "resets_at": 1781400000}
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try CodexUsageReader.parseRegistry(data: registry, now: Date(timeIntervalSince1970: 1_781_388_300))
        let account = try XCTUnwrap(snapshot.accounts.first)

        XCTAssertEqual(account.loginWarning, .quotaUnavailable)
        XCTAssertFalse(account.needsLogin)
        XCTAssertNil(account.fiveHourWindow)
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
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"new-token","account_id":"org"}}
        """.data(using: .utf8)!.write(to: authURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: authURL.path)

        let snapshot = codexReader(homeDirectory: temp).read()

        XCTAssertNil(snapshot.accounts.first?.loginWarning)
    }

    private func checkCodexReadUsesActiveAuthAccountWhenRegistryActiveIsStale() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try """
        {
          "schema_version": 3,
          "active_account_key": "acct-a",
          "accounts": [
            {"account_key":"acct-a","email":"locked@example.com","chatgpt_account_id":"chatgpt-a","agentbar_auth_error":{"status_code":401,"detected_at":1000}},
            {"account_key":"acct-b","email":"current@example.com","chatgpt_account_id":"chatgpt-b"}
          ]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        let credentialExpiry = Date(timeIntervalSince1970: 1_800_000_000)
        let accessToken = "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(#"{"exp":1800000000}"#))."
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"\(accessToken)","account_id":"chatgpt-b"}}
        """.data(using: .utf8)!.write(to: temp.appending(path: ".codex/auth.json"))
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"wrong-token","account_id":"chatgpt-b"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-a.auth.json"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: accountDir.appending(path: "acct-a.auth.json").path)

        let snapshot = codexReader(homeDirectory: temp).read()

        XCTAssertFalse(try XCTUnwrap(snapshot.accounts.first { $0.id == "acct-a" }).isActive)
        XCTAssertEqual(snapshot.accounts.first { $0.id == "acct-a" }?.loginWarning, .forcedLogout)
        XCTAssertTrue(try XCTUnwrap(snapshot.accounts.first { $0.id == "acct-b" }).isActive)
        XCTAssertEqual(snapshot.accounts.first { $0.id == "acct-b" }?.accessTokenExpiresAt, credentialExpiry)
    }

    private func checkCodexReadUsesAuthEmailToDisambiguateDuplicateWorkspaceIDs() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try """
        {
          "schema_version": 3,
          "active_account_key": "user-old::workspace-2",
          "accounts": [
            {"account_key":"user-old::workspace-2","email":"chatgpt1@example.com","chatgpt_account_id":"workspace-2"},
            {"account_key":"user-current::workspace-2","email":"person@example.com","account_name":"Workspace 2","chatgpt_account_id":"workspace-2","agentbar_auth_error":{"status_code":401,"detected_at":1000}}
          ]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        let activeAuthURL = temp.appending(path: ".codex/auth.json")
        try authJSON(accessToken: "current-token", accountID: "workspace-2", email: "person@example.com")
            .data(using: .utf8)!
            .write(to: activeAuthURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: activeAuthURL.path)

        let snapshot = codexReader(homeDirectory: temp).read()

        XCTAssertFalse(try XCTUnwrap(snapshot.accounts.first { $0.id == "user-old::workspace-2" }).isActive)
        let current = try XCTUnwrap(snapshot.accounts.first { $0.id == "user-current::workspace-2" })
        XCTAssertTrue(current.isActive)
        XCTAssertNil(current.loginWarning)
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
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","session_id":"session-1","payload":{"cwd":"/Users/tester/Desktop/Coding/AgentBar","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.points.first?.sessionID, "session-1")
        XCTAssertEqual(metrics.points.first?.sessionTitle, "Fix high CPU usage in AgentBar")
        XCTAssertEqual(metrics.points.first?.projectName, "AgentBar")
    }

    private func checkCodexSessionJsonlBuildsTaskLifecycle() throws {
        let data = """
        {"type":"event_msg","timestamp":"2026-07-10T07:00:00Z","payload":{"type":"task_started","turn_id":"turn-1","started_at":1783666800}}
        {"type":"turn_context","timestamp":"2026-07-10T07:00:01Z","payload":{"cwd":"/Users/test/AgentBar","model":"gpt-5.6-terra"}}
        {"type":"event_msg","timestamp":"2026-07-10T07:00:02Z","payload":{"type":"user_message","message":"Build the live task center"}}
        {"type":"event_msg","timestamp":"2026-07-10T07:00:10Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"reasoning_output_tokens":10,"total_tokens":140}}}}
        {"type":"event_msg","timestamp":"2026-07-10T07:01:00Z","payload":{"type":"task_complete","turn_id":"turn-1","completed_at":1783666860,"duration_ms":60000}}
        {"type":"event_msg","timestamp":"2026-07-10T07:02:00Z","payload":{"type":"task_started","turn_id":"turn-2","started_at":1783666920}}
        {"type":"event_msg","timestamp":"2026-07-10T07:02:01Z","payload":{"type":"user_message","message":"Set project budgets"}}
        {"type":"event_msg","timestamp":"2026-07-10T07:02:10Z","payload":{"type":"agent_message","message":"I will implement repository budgets."}}
        {"type":"event_msg","timestamp":"2026-07-10T07:02:30Z","payload":{"type":"task_complete","turn_id":"turn-2","completed_at":1783666950,"duration_ms":30000}}
        {"type":"event_msg","timestamp":"2026-07-10T07:03:00Z","payload":{"type":"task_started","turn_id":"turn-3","started_at":1783666980}}
        {"type":"event_msg","timestamp":"2026-07-10T07:03:01Z","payload":{"type":"user_message","message":"Run every plan"}}
        {"type":"event_msg","timestamp":"2026-07-10T07:04:00Z","payload":{"type":"task_started","turn_id":"turn-4","started_at":1783667040}}
        {"type":"event_msg","timestamp":"2026-07-10T07:04:01Z","payload":{"type":"user_message","message":"Continue"}}
        {"type":"event_msg","timestamp":"2026-07-10T07:04:20Z","payload":{"type":"agent_message","message":"Still working."}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: data, sessionID: "session-1")
        let task = try XCTUnwrap(metrics.tasks.first)
        XCTAssertEqual(metrics.tasks.count, 4)
        XCTAssertEqual(task.id, "turn-1")
        XCTAssertEqual(task.sessionID, "session-1")
        XCTAssertEqual(task.projectName, "AgentBar")
        XCTAssertEqual(task.cwd, "/Users/test/AgentBar")
        XCTAssertEqual(task.tokens.total, 140)
        XCTAssertEqual(task.models, ["gpt-5.6-terra"])
        XCTAssertEqual(task.terminalState, .completed)
        XCTAssertEqual(task.state(at: Date(timeIntervalSince1970: 1_783_666_900)), .completed)
        XCTAssertEqual(task.duration(at: task.completedAt!), 60, accuracy: 0.001)
        XCTAssertEqual(metrics.tasks[2].terminalState, .interrupted)
        XCTAssertEqual(metrics.tasks[2].completedAt, Date(timeIntervalSince1970: 1_783_667_040))
        let currentTask = try XCTUnwrap(metrics.tasks.last)
        XCTAssertEqual(currentTask.title, "Continue")
        XCTAssertEqual(currentTask.state(at: Date(timeIntervalSince1970: 1_783_667_400)), .waiting)
        XCTAssertEqual(currentTask.state(at: Date(timeIntervalSince1970: 1_783_668_960)), .interrupted)
        XCTAssertEqual(currentTask.duration(at: Date(timeIntervalSince1970: 1_783_668_960)), 20, accuracy: 0.001)
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

    @MainActor
    private func checkCodexUsageAPISyncerUpdatesRegistryWithoutCodexAuthRuntime() async throws {
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
                if request.url == CodexUsageAPISyncer.resetCreditsEndpoint {
                    return CodexUsageAPIResponse(statusCode: 404, data: Data())
                }
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

        let result = await syncer.refreshUsage()
        XCTAssertEqual(result, .success)

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

    @MainActor
    private func checkCodexUsageAPISyncerRefreshesInactiveAccountsHourly() async throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-b","email":"stale@example.com","last_usage_at":1000},{"account_key":"acct-a","email":"active@example.com"},{"account_key":"acct-c","email":"recent@example.com","last_usage_at":4000},{"account_key":"acct-d","email":"failed@example.com","last_usage_at":1000}]}
        """.data(using: .utf8)!.write(to: registryURL)
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"active-token","account_id":"active-chatgpt-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-a.auth.json"))
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"other-token","account_id":"other-chatgpt-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-b.auth.json"))
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"recent-token","account_id":"recent-chatgpt-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-c.auth.json"))
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"failed-token","account_id":"failed-chatgpt-id"}}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "acct-d.auth.json"))

        let requestRecorder = UsageAPIRequestRecorder()
        let syncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            now: { Date(timeIntervalSince1970: 4_600) },
            usageClient: { request, _ in
                requestRecorder.record(request)
                let accountID = request.value(forHTTPHeaderField: "ChatGPT-Account-Id")
                if request.url == CodexUsageAPISyncer.usageEndpoint,
                   accountID == "active-chatgpt-id",
                   let data = try? Data(contentsOf: registryURL),
                   var registry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    registry["concurrent_marker"] = "preserved"
                    try CodexAccountStorage(homeDirectory: temp).writeRegistry(registry)
                }
                if accountID == "failed-chatgpt-id" {
                    return CodexUsageAPIResponse(statusCode: 500, data: Data())
                }
                return CodexUsageAPIResponse(
                    statusCode: 200,
                    data: #"{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1781400000}}}"#.data(using: .utf8)!
                )
            }
        )

        let result = await syncer.refreshUsage()
        XCTAssertEqual(result, .success)
        XCTAssertEqual(requestRecorder.accountIDs, [
            "active-chatgpt-id", "active-chatgpt-id",
            "other-chatgpt-id", "other-chatgpt-id",
            "failed-chatgpt-id"
        ])
        let accounts = try registryAccounts(from: registryURL)
        XCTAssertNotNil(accounts.first { $0["account_key"] as? String == "acct-a" }?["last_usage"])
        XCTAssertNotNil(accounts.first { $0["account_key"] as? String == "acct-b" }?["last_usage"])
        XCTAssertEqual(accounts.first { $0["account_key"] as? String == "acct-b" }?["agentbar_last_usage_refresh_at"] as? Double, 4_600)
        XCTAssertNil(accounts.first { $0["account_key"] as? String == "acct-c" }?["last_usage"])
        XCTAssertNil(accounts.first { $0["account_key"] as? String == "acct-d" }?["last_usage"])
        XCTAssertEqual(accounts.first { $0["account_key"] as? String == "acct-d" }?["agentbar_last_usage_refresh_at"] as? Double, 4_600)
        let registry = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any])
        XCTAssertEqual(registry["concurrent_marker"] as? String, "preserved")

        let secondResult = await syncer.refreshUsage()
        XCTAssertEqual(secondResult, .success)
        XCTAssertEqual(requestRecorder.requestCount, 7)
    }

    @MainActor
    private func checkCodexUsageAPISyncerAlwaysFetchesDetailedResetExpiryDates() async throws {
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
            }
        )

        let result = await syncer.refreshUsage()
        XCTAssertEqual(result, .success)
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

    @MainActor
    private func checkCodexUsageAPISyncerPersists401AndClearsItAfterSuccess() async throws {
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

        let unauthorizedResult = await unauthorizedSyncer.refreshUsage()
        XCTAssertEqual(unauthorizedResult, .failed("HTTP 401"))
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

        let successResult = await successSyncer.refreshUsage()
        XCTAssertEqual(successResult, .success)
        account = try registryAccount(from: registryURL)
        XCTAssertNil(account["agentbar_auth_error"])
    }

    @MainActor
    private func checkCodexUsageAPISyncerUsesNewerActiveAuthForActiveAccount() async throws {
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

        let result = await syncer.refreshUsage()
        XCTAssertEqual(result, .success)
        XCTAssertTrue((try String(contentsOf: staleSnapshotURL)).contains("new-token"))
        XCTAssertNil(try registryAccount(from: registryURL)["agentbar_auth_error"])
    }

    @MainActor
    private func checkCodexUsageAPISyncerRefreshesActiveAuthAccountWhenRegistryActiveIsStale() async throws {
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
            {"account_key":"acct-a","email":"locked@example.com","chatgpt_account_id":"chatgpt-a","agentbar_auth_error":{"status_code":401,"detected_at":1000}},
            {"account_key":"acct-b","email":"current@example.com","chatgpt_account_id":"chatgpt-b"}
          ]
        }
        """.data(using: .utf8)!.write(to: registryURL)
        try """
        {"auth_mode":"chatgpt","tokens":{"access_token":"current-token","account_id":"chatgpt-b"}}
        """.data(using: .utf8)!.write(to: temp.appending(path: ".codex/auth.json"))

        let syncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            usageClient: { request, _ in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer current-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "chatgpt-b")
                return CodexUsageAPIResponse(
                    statusCode: 200,
                    data: #"{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1781400000}}}"#.data(using: .utf8)!
                )
            }
        )

        let result = await syncer.refreshUsage()
        XCTAssertEqual(result, .success)
        let accounts = try registryAccounts(from: registryURL)
        XCTAssertNil(accounts.first { $0["account_key"] as? String == "acct-a" }?["last_usage"])
        XCTAssertNotNil(accounts.first { $0["account_key"] as? String == "acct-b" }?["last_usage"])
    }

    @MainActor
    private func checkCodexUsageAPISyncerUsesAuthEmailToDisambiguateDuplicateWorkspaceIDs() async throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {
          "schema_version": 3,
          "active_account_key": "user-old::workspace-2",
          "accounts": [
            {"account_key":"user-old::workspace-2","email":"chatgpt1@example.com","chatgpt_account_id":"workspace-2"},
            {"account_key":"user-current::workspace-2","email":"person@example.com","account_name":"Workspace 2","chatgpt_account_id":"workspace-2","agentbar_auth_error":{"status_code":401,"detected_at":1000}}
          ]
        }
        """.data(using: .utf8)!.write(to: registryURL)
        try authJSON(accessToken: "current-token", accountID: "workspace-2", email: "person@example.com")
            .data(using: .utf8)!
            .write(to: temp.appending(path: ".codex/auth.json"))

        let syncer = CodexUsageAPISyncer(
            homeDirectory: temp,
            usageClient: { request, _ in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer current-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "workspace-2")
                return CodexUsageAPIResponse(
                    statusCode: 200,
                    data: #"{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1781400000}}}"#.data(using: .utf8)!
                )
            }
        )

        let result = await syncer.refreshUsage()
        XCTAssertEqual(result, .success)
        let accounts = try registryAccounts(from: registryURL)
        XCTAssertNil(accounts.first { $0["account_key"] as? String == "user-old::workspace-2" }?["last_usage"])
        let current = try XCTUnwrap(accounts.first { $0["account_key"] as? String == "user-current::workspace-2" })
        XCTAssertNotNil(current["last_usage"])
        XCTAssertNil(current["agentbar_auth_error"])
    }

    private func checkCodexRecoveryLoginCommandSnapshotsAuthAfterLogin() {
        let storage = CodexAccountStorage(homeDirectory: URL(fileURLWithPath: "/tmp/agentbar-codex-home"))

        XCTAssertEqual(
            storage.recoveryLoginCommand(accountID: "user-a::org"),
            "codex login && mkdir -p '/tmp/agentbar-codex-home/.codex/accounts' && cp '/tmp/agentbar-codex-home/.codex/auth.json' '/tmp/agentbar-codex-home/.codex/accounts/dXNlci1hOjpvcmc.auth.json' && /usr/bin/notifyutil -p com.agentbar.codexRecoveryLoginFinished"
        )
    }

    private func checkCodexAccessTokenUpdaterMarksTokenBackedSnapshot() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registryURL = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-token","accounts":[{"account_key":"acct-token","email":"token@example.com","agentbar_auth_error":{"status_code":401}}]}
        """.data(using: .utf8)!.write(to: registryURL)
        let authData = """
        {"auth_mode":"chatgpt","tokens":{"access_token":"fresh-token","account_id":"acct-token"}}
        """.data(using: .utf8)!

        try CodexAccountAccessTokenUpdater(homeDirectory: temp).writeTokenBackedSnapshot(authData, accountID: "acct-token")

        let account = try registryAccount(from: registryURL)
        XCTAssertEqual(account["agentbar_token_backed"] as? Bool, true)
        XCTAssertNil(account["agentbar_auth_error"])
        XCTAssertEqual(try Data(contentsOf: accountDir.appending(path: "acct-token.auth.json")), authData)
        XCTAssertEqual(try Data(contentsOf: temp.appending(path: ".codex/auth.json")), authData)
    }

    private func checkCodexAccountStorageCentralizesRegistryAuthAndRecoveryPaths() {
        let home = URL(fileURLWithPath: "/tmp/agentbar-codex-home")
        let storage = CodexAccountStorage(homeDirectory: home)

        XCTAssertEqual(storage.registryURL.path, "/tmp/agentbar-codex-home/.codex/accounts/registry.json")
        XCTAssertEqual(storage.activeAuthURL.path, "/tmp/agentbar-codex-home/.codex/auth.json")
        XCTAssertEqual(storage.accountAuthURL(for: "user-a::org").path, "/tmp/agentbar-codex-home/.codex/accounts/dXNlci1hOjpvcmc.auth.json")
        XCTAssertEqual(storage.accountAuthURL(for: "plain-account").path, "/tmp/agentbar-codex-home/.codex/accounts/plain-account.auth.json")
        XCTAssertTrue(storage.recoveryLoginCommand(accountID: "user-a::org").contains("dXNlci1hOjpvcmc.auth.json"))
    }

    private func checkCodexAccountStorageParsesAccessTokenExpiration() throws {
        let expiry = Date(timeIntervalSince1970: 1_800_086_400)
        let auth = authJSON(
            accessToken: accessToken(expiry: expiry),
            accountID: "acct-a",
            email: "a@example.com"
        ).data(using: .utf8)!

        XCTAssertEqual(CodexAccountStorage.accessTokenExpiration(from: auth), expiry)
        XCTAssertNil(CodexAccountStorage.accessTokenExpiration(
            from: Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"broken"}}"#.utf8)
        ))
        XCTAssertNil(CodexAccountStorage.accessTokenExpiration(
            from: Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"secret"}"#.utf8)
        ))
    }

    private func checkCodexReadUsesPerAccountAccessTokenExpirations() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let storage = CodexAccountStorage(homeDirectory: temp)
        try FileManager.default.createDirectory(at: storage.accountsDirectory, withIntermediateDirectories: true)
        try """
        {
          "schema_version": 3,
          "active_account_key": "acct-a",
          "accounts": [
            {"account_key":"acct-a","email":"a@example.com","chatgpt_account_id":"acct-a"},
            {"account_key":"acct-b","email":"b@example.com","chatgpt_account_id":"acct-b"}
          ]
        }
        """.data(using: .utf8)!.write(to: storage.registryURL)

        let activeExpiry = Date(timeIntervalSince1970: 1_800_086_400)
        let staleActiveExpiry = activeExpiry.addingTimeInterval(-86_400)
        let inactiveExpiry = activeExpiry.addingTimeInterval(86_400)
        try authJSON(accessToken: accessToken(expiry: activeExpiry), accountID: "acct-a", email: "a@example.com")
            .data(using: .utf8)!.write(to: storage.activeAuthURL)
        try authJSON(accessToken: accessToken(expiry: staleActiveExpiry), accountID: "acct-a", email: "a@example.com")
            .data(using: .utf8)!.write(to: storage.accountAuthURL(for: "acct-a"))
        try authJSON(accessToken: accessToken(expiry: inactiveExpiry), accountID: "acct-b", email: "b@example.com")
            .data(using: .utf8)!.write(to: storage.accountAuthURL(for: "acct-b"))

        let accounts = codexReader(homeDirectory: temp).read().accounts

        XCTAssertEqual(accounts.first { $0.id == "acct-a" }?.accessTokenExpiresAt, activeExpiry)
        XCTAssertEqual(accounts.first { $0.id == "acct-b" }?.accessTokenExpiresAt, inactiveExpiry)

        try FileManager.default.removeItem(at: storage.activeAuthURL)
        let fallbackAccounts = codexReader(homeDirectory: temp).read().accounts
        XCTAssertEqual(fallbackAccounts.first { $0.id == "acct-a" }?.accessTokenExpiresAt, staleActiveExpiry)

        let unrelatedExpiry = activeExpiry.addingTimeInterval(2 * 86_400)
        try authJSON(accessToken: accessToken(expiry: unrelatedExpiry), accountID: "not-in-registry", email: "other@example.com")
            .data(using: .utf8)!.write(to: storage.activeAuthURL)
        let mismatchedAccounts = codexReader(homeDirectory: temp).read().accounts
        XCTAssertEqual(mismatchedAccounts.first { $0.id == "acct-a" }?.accessTokenExpiresAt, staleActiveExpiry)
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
    private func checkRefreshSyncsCodexUsageAPIBeforeReadingUsage() async {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "detailedResetCreditsEnabled")
        let settings = SettingsStore(defaults: defaults)
        let expectation = expectation(description: "refresh completed")
        let recorder = RefreshOrderRecorder()
        let now = Date()
        let activeAccount = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 8, weeklyUsed: 55, now: now)
        let claudePoint = UsagePoint(
            service: .claudeCode,
            model: "claude-opus",
            date: now,
            tokens: TokenTotals(input: 10, cachedInput: 0, output: 15, reasoningOutput: 0, total: 25),
            estimatedCostUSD: nil
        )
        let store = UsageStore(
            settings: settings,
            codexUsageSynchronizer: {
                recorder.record("detailed-sync")
                return .failed("expired token")
            },
            codexUsageReader: {
                XCTAssertEqual(recorder.events, ["detailed-sync"])
                recorder.record("codex-read")
                return UsageSnapshot(
                    service: .codex,
                    status: .live,
                    accounts: [
                        activeAccount
                    ],
                    points: [],
                    securityNotes: ["local note"],
                    refreshedAt: now,
                    pricingFingerprint: Pricing.fingerprint
                )
            },
            claudeUsageReader: {
                XCTAssertEqual(recorder.events, ["detailed-sync", "codex-read"])
                recorder.record("claude-read")
                expectation.fulfill()
                return UsageSnapshot(service: .claudeCode, status: .unavailable, accounts: [], points: [claudePoint], securityNotes: ["test"], refreshedAt: now, pricingFingerprint: Pricing.fingerprint)
            }
        )
        store.refresh(force: true)

        await fulfillment(of: [expectation], timeout: 2)
        await waitForStoreRefresh(store)
        XCTAssertEqual(recorder.events, ["detailed-sync", "codex-read", "claude-read"])
        XCTAssertEqual(store.snapshots[.codex]?.securityNotes, [
            "local note",
            "Codex usage API sync failed: expired token; using local registry and session cache."
        ])
        XCTAssertEqual(store.snapshots[.claudeCode]?.points, [claudePoint])
        XCTAssertEqual(store.accounts.map(\.id), ["active"])
        XCTAssertEqual(store.points, [claudePoint])
        XCTAssertEqual(store.menuBarTitle, "5H 92%  WK 45%")
    }

    @MainActor
    private func waitForStoreRefresh(_ store: UsageStore) async {
        for _ in 0..<20 where store.accounts.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
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
        XCTAssertEqual(L.text("dark_theme", .chinese), "深色主题")
    }

    @MainActor
    private func checkCodexSidebarQuotaOverlaySettingPersists() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = SettingsStore(defaults: defaults)
        XCTAssertFalse(initial.showCodexSidebarQuotaOverlay)
        XCTAssertFalse(initial.codexSidebarQuotaOverlayIndependent)
        XCTAssertFalse(initial.didCompleteQuotaWidgetOnboarding)

        initial.showCodexSidebarQuotaOverlay = true
        initial.codexSidebarQuotaOverlayIndependent = true
        initial.didCompleteQuotaWidgetOnboarding = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.showCodexSidebarQuotaOverlay)
        XCTAssertTrue(reloaded.codexSidebarQuotaOverlayIndependent)
        XCTAssertTrue(reloaded.didCompleteQuotaWidgetOnboarding)
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

        let snapshot = codexReader(homeDirectory: temp).read()
        let active = try XCTUnwrap(snapshot.accounts.first { $0.id == "active" })
        let inactive = try XCTUnwrap(snapshot.accounts.first { $0.id == "inactive" })

        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 90)
        XCTAssertEqual(active.weeklyWindow?.usedPercent, 80)
        XCTAssertEqual(inactive.fiveHourWindow?.usedPercent, 40)
        XCTAssertEqual(inactive.weeklyWindow?.usedPercent, 30)
    }

    private func checkCodexReadDoesNotRestoreRemovedFiveHourLimitFromSessions() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/07")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {
          "schema_version": 3,
          "active_account_key": "active",
          "accounts": [{
            "account_key": "active",
            "last_usage": {
              "primary": {"used_percent": 5, "window_minutes": 10080, "resets_at": 1784538977}
            }
          }]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","timestamp":"2026-07-13T06:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":12,"window_minutes":300,"resets_at":1783936800},"secondary":{"used_percent":34,"window_minutes":10080,"resets_at":1784538977}}}}
        """.data(using: .utf8)!.write(to: sessionDir.appending(path: "current.jsonl"))

        let account = try XCTUnwrap(codexReader(homeDirectory: temp).read().accounts.first)

        XCTAssertNil(account.fiveHourWindow)
        XCTAssertEqual(account.weeklyWindow?.usedPercent, 5)
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

        let snapshot = codexReader(homeDirectory: temp).read()
        let active = try XCTUnwrap(snapshot.accounts.first)

        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 9)
        XCTAssertEqual(active.weeklyWindow?.usedPercent, 11)
    }

    private func checkCodexReadDoesNotInventLastActivityForAccountsMissingUsageTimestamp() throws {
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
            {"account_key": "active", "email": "active@example.com", "plan": "team"},
            {"account_key": "inactive", "email": "inactive@example.com", "plan": "team"}
          ]
        }
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:00:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":9,"window_minutes":300,"resets_at":1781410000},"secondary":{"used_percent":11,"window_minutes":10080,"resets_at":1781910000},"plan_type":"team"},"rate_limit_reset_credits":{"available_count":1}}}
        """.data(using: .utf8)!.write(to: sessionDir.appending(path: "current.jsonl"))

        let snapshot = codexReader(homeDirectory: temp).read()
        let active = try XCTUnwrap(snapshot.accounts.first { $0.id == "active" })
        let inactive = try XCTUnwrap(snapshot.accounts.first { $0.id == "inactive" })

        XCTAssertEqual(active.lastUpdated, ISO8601DateFormatter().date(from: "2026-06-14T06:00:00Z"))
        XCTAssertEqual(active.fiveHourWindow?.usedPercent, 9)
        XCTAssertNil(inactive.lastUpdated)
        XCTAssertNil(inactive.fiveHourWindow)
        XCTAssertNil(inactive.weeklyWindow)
        XCTAssertNil(inactive.resetCredits)
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

        var snapshot = codexReader(homeDirectory: temp).read()
        XCTAssertEqual(snapshot.accounts.first?.fiveHourWindow?.usedPercent, 10)
        XCTAssertEqual(snapshot.points.reduce(0) { $0 + $1.tokens.total }, 2)

        try """
        {"type":"event_msg","timestamp":"2026-06-14T06:00:00Z","payload":{"info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},"rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1781410000},"secondary":{"used_percent":20,"window_minutes":10080,"resets_at":1781910000}}}}
        {"type":"event_msg","timestamp":"2026-06-14T07:00:00.000Z","payload":{"info":{"last_token_usage":{"input_tokens":3,"cached_input_tokens":0,"output_tokens":4,"reasoning_output_tokens":0,"total_tokens":7}},"rate_limits":{"primary":{"used_percent":35,"window_minutes":300,"resets_at":1781420000},"secondary":{"used_percent":45,"window_minutes":10080,"resets_at":1781920000}}}}
        """.data(using: .utf8)!.write(to: sessionFile)

        snapshot = codexReader(homeDirectory: temp).read()

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

        var snapshot = codexReader(homeDirectory: temp).read()
        XCTAssertEqual(snapshot.points.count, 1)

        try FileManager.default.removeItem(at: sessionFile)
        snapshot = codexReader(homeDirectory: temp).read()

        XCTAssertTrue(snapshot.points.isEmpty)
        XCTAssertNil(snapshot.accounts.first?.fiveHourWindow)
    }

    private func checkForkedSessionHistoryIsDeduplicated() throws {
        CodexUsageReader.resetSessionMetricsCacheForTesting()
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temp)
            CodexUsageReader.resetSessionMetricsCacheForTesting()
        }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = temp.appending(path: ".codex/sessions/2026/07")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"schema_version":3,"active_account_key":"active","accounts":[{"account_key":"active","email":"active@example.com","plan":"team"}]}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        let parentHistory = """
        {"type":"event_msg","timestamp":"2026-07-10T07:00:00Z","payload":{"type":"task_started","turn_id":"shared-turn","started_at":1783666800}}
        {"type":"turn_context","timestamp":"2026-07-10T07:00:01Z","payload":{"cwd":"/repo/AgentBar","model":"gpt-5.6-terra"}}
        {"type":"event_msg","timestamp":"2026-07-10T07:00:02Z","payload":{"type":"user_message","message":"Build project billing"}}
        {"type":"event_msg","timestamp":"2026-07-10T07:00:10Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":8,"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":10},"total_token_usage":{"input_tokens":8,"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":10}}}}
        {"type":"event_msg","timestamp":"2026-07-10T07:00:20Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":8,"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":10},"total_token_usage":{"input_tokens":8,"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":10}}}}
        {"type":"event_msg","timestamp":"2026-07-10T07:01:00Z","payload":{"type":"task_complete","turn_id":"shared-turn","completed_at":1783666860}}
        """.data(using: .utf8)!
        let forkedHistory = """
        {"type":"event_msg","timestamp":"2026-07-10T08:00:00Z","payload":{"type":"task_started","turn_id":"shared-turn","started_at":1783666800}}
        {"type":"turn_context","timestamp":"2026-07-10T08:00:01Z","payload":{"cwd":"/repo/AgentBar","model":"gpt-5.6-terra"}}
        {"type":"event_msg","timestamp":"2026-07-10T08:00:02Z","payload":{"type":"user_message","message":"Build project billing"}}
        {"type":"event_msg","timestamp":"2026-07-10T08:00:10Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":8,"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":10},"total_token_usage":{"input_tokens":8,"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":10}}}}
        {"type":"event_msg","timestamp":"2026-07-10T08:01:00Z","payload":{"type":"task_complete","turn_id":"shared-turn","completed_at":1783666860}}
        """.data(using: .utf8)!
        try parentHistory.write(to: sessionDir.appending(path: "parent.jsonl"))
        try forkedHistory.write(to: sessionDir.appending(path: "fork.jsonl"))

        let snapshot = codexReader(homeDirectory: temp).read()

        XCTAssertEqual(snapshot.points.count, 1)
        XCTAssertEqual(snapshot.points.first?.tokens.total, 10)
        XCTAssertEqual(snapshot.tasks.count, 1)
        XCTAssertEqual(snapshot.tasks.first?.id, "shared-turn")
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

        let snapshot = codexReader(homeDirectory: temp).read()
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

        let snapshot = codexReader(homeDirectory: temp).read()
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

        let snapshot = codexReader(homeDirectory: temp).read()

        XCTAssertEqual(snapshot.points.count, 0)
        XCTAssertEqual(snapshot.accounts.first?.tokens.total, 0)
        XCTAssertTrue(snapshot.securityNotes.first?.contains("1 over the 10 MB file limit") == true)
        XCTAssertEqual(UsageInsights.dataSourceHealth(snapshots: [.codex: snapshot]).rows.first?.note, snapshot.securityNotes.first)
    }

    private func checkSessionFileCapSkipsAreReported() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let sessionDir = temp.appending(path: ".codex/sessions/2026/06")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        for index in 0...CodexUsageReader.maximumSessionFiles {
            try "{}".data(using: .utf8)!.write(to: sessionDir.appending(path: "\(index).jsonl"))
        }

        let snapshot = codexReader(homeDirectory: temp).read()

        XCTAssertTrue(snapshot.securityNotes.first?.contains("1 beyond the 1000 file scan cap") == true)
        XCTAssertEqual(UsageInsights.dataSourceHealth(snapshots: [.codex: snapshot]).rows.first?.note, snapshot.securityNotes.first)
    }

    private func checkCodexReadWarnsWhenSessionAccessIsDenied() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let sessionFile = temp.appending(path: ".codex/sessions/2026/06/blocked.jsonl")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionFile.path)
            try? FileManager.default.removeItem(at: temp)
        }
        let accountDir = temp.appending(path: ".codex/accounts")
        let sessionDir = sessionFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"schema_version":3,"active_account_key":"active","accounts":[{"account_key":"active","email":"active@example.com"}]}
        """.data(using: .utf8)!.write(to: accountDir.appending(path: "registry.json"))
        try "{}".data(using: .utf8)!.write(to: sessionFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sessionFile.path)

        let snapshot = codexReader(homeDirectory: temp).read()
        let health = UsageInsights.dataSourceHealth(snapshots: [.codex: snapshot])

        XCTAssertEqual(snapshot.status, .needsAuthorization)
        XCTAssertTrue(snapshot.securityNotes.first?.contains("AgentBar cannot read local Codex data") == true)
        XCTAssertTrue(snapshot.securityNotes.first?.contains("Full Disk Access") == true)
        XCTAssertEqual(health.issueCount, 1)
        XCTAssertEqual(health.rows.first?.note, snapshot.securityNotes.first)
    }

    private func checkOpenAIModelPricingCalculatesPointCost() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","payload":{"info":{"model":"gpt-5.1","last_token_usage":{"input_tokens":1000000,"cached_input_tokens":100000,"output_tokens":100000,"reasoning_output_tokens":0,"total_tokens":1100000}}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.points.count, 1)
        XCTAssertEqual(metrics.points[0].estimatedCostUSD ?? 0, Decimal(string: "2.1375"))
    }

    private func checkGPT56BedrockPricingCalculatesPointCost() throws {
        let jsonl = """
        {"type":"event_msg","timestamp":"2026-06-13T22:06:12.184Z","payload":{"info":{"model":"openai.gpt-5.6-terra","last_token_usage":{"input_tokens":1000000,"cached_input_tokens":100000,"output_tokens":100000,"reasoning_output_tokens":0,"total_tokens":1100000}}}}
        """.data(using: .utf8)!

        let metrics = try CodexUsageReader.parseSessionJsonl(data: jsonl)

        XCTAssertEqual(metrics.points.map(\.model), ["gpt-5.6-terra"])
        XCTAssertEqual(metrics.points[0].estimatedCostUSD ?? 0, Decimal(string: "3.775"))
        XCTAssertEqual(
            Pricing.cost(model: "gpt-5.6-luna", input: 0, output: 0, cacheRead: 0, cacheCreation: 1_000_000),
            Decimal(string: "1.25")
        )
    }

    private func checkPricingNormalizesProviderAndDateSuffixes() {
        XCTAssertEqual(Pricing.normalize(model: "openai/GPT-5.4@20260131"), "gpt-5.4")
        XCTAssertEqual(Pricing.normalize(model: "openai.gpt-5.6-sol"), "gpt-5.6-sol")
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
    private func checkMenuBarDefaultsToActiveQuotaWithoutWarningMark() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let store = UsageStore(settings: settings, codexUsageSynchronizer: { .success })
        let now = Date()
        let inactive = testAccount(id: "inactive", name: "inactive@example.com", fiveHourUsed: 90, weeklyUsed: 40, now: now)
        var active = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 31, weeklyUsed: 8, now: now)
        active.isActive = true
        active.loginWarning = .forcedLogout
        store.applyTestData(accounts: [inactive, active], points: [])

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

        var weeklyOnly = testAccount(id: "weekly-only", name: "weekly@example.com", fiveHourUsed: 0, weeklyUsed: 5, now: now)
        weeklyOnly.fiveHourWindow = nil
        weeklyOnly.isActive = true
        let staleInactive = testAccount(id: "stale", name: "stale@example.com", fiveHourUsed: 20, weeklyUsed: 10, now: now)
        store.applyTestData(accounts: [staleInactive, weeklyOnly])

        XCTAssertEqual(store.menuBarTitle, "WK 95%")
        XCTAssertEqual(store.popoverHeaderQuotaTitle, "WK 95% remaining")
        XCTAssertTrue(store.accounts.allSatisfy { $0.fiveHourWindow == nil })
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
    private func checkBudgetSettingsPersist() {
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
    }

    private func checkQuotaCapacityHistoryEstimatesFromPercentAndTokenDelta() {
        let firstDate = Date(timeIntervalSince1970: 1_781_388_300)
        let secondDate = firstDate.addingTimeInterval(3_600)
        var firstAccount = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: firstDate)
        firstAccount.isActive = true
        var secondAccount = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 15, weeklyUsed: 22, now: firstDate)
        secondAccount.isActive = true
        let points = [
            UsagePoint(
                service: .codex,
                model: "codex-local",
                date: firstDate.addingTimeInterval(1_800),
                tokens: TokenTotals(input: 600, cachedInput: 0, output: 400, reasoningOutput: 0, total: 1_000),
                estimatedCostUSD: nil
            )
        ]

        let first = QuotaCapacityHistory(samples: []).appendingSample(
            account: firstAccount,
            points: [],
            now: firstDate,
            minimumInterval: 3_600
        )
        let second = first.appendingSample(
            account: secondAccount,
            points: points,
            now: secondDate,
            minimumInterval: 3_600
        )

        XCTAssertEqual(second.samples.count, 2)
        XCTAssertNil(second.samples[0].estimatedFiveHourTotalTokens)
        XCTAssertEqual(second.samples[1].tokensSincePreviousSample, 1_000)
        XCTAssertEqual(second.samples[1].estimatedFiveHourTotalTokens, 20_000)
        XCTAssertEqual(second.samples[1].estimatedWeeklyTotalTokens, 50_000)
    }

    private func checkQuotaCapacityHistoryDoesNotEstimateAcrossAccountSwitches() {
        let firstDate = Date(timeIntervalSince1970: 1_781_388_300)
        let secondDate = firstDate.addingTimeInterval(3_600)
        let thirdDate = secondDate.addingTimeInterval(3_600)
        var firstAccount = testAccount(id: "first", name: "first@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: firstDate)
        firstAccount.isActive = true
        var secondAccount = testAccount(id: "second", name: "second@example.com", fiveHourUsed: 10, weeklyUsed: 30, now: secondDate)
        secondAccount.isActive = true
        var laterSecondAccount = testAccount(id: "second", name: "second@example.com", fiveHourUsed: 15, weeklyUsed: 35, now: thirdDate)
        laterSecondAccount.isActive = true
        laterSecondAccount.fiveHourWindow?.resetsAt = secondAccount.fiveHourWindow?.resetsAt
        laterSecondAccount.weeklyWindow?.resetsAt = secondAccount.weeklyWindow?.resetsAt
        let points = [
            UsagePoint(
                service: .codex,
                model: "codex-local",
                date: secondDate.addingTimeInterval(600),
                tokens: TokenTotals(input: 600, cachedInput: 0, output: 400, reasoningOutput: 0, total: 1_000),
                estimatedCostUSD: nil
            )
        ]

        let first = QuotaCapacityHistory(samples: []).appendingSample(
            account: firstAccount,
            points: [],
            now: firstDate,
            minimumInterval: 3_600
        )
        let switched = first.appendingSample(
            account: secondAccount,
            points: points,
            now: secondDate,
            minimumInterval: 3_600
        )
        let estimated = switched.appendingSample(
            account: laterSecondAccount,
            points: points,
            now: thirdDate,
            minimumInterval: 3_600
        )

        XCTAssertEqual(switched.samples[1].tokensSincePreviousSample, 0)
        XCTAssertNil(switched.samples[1].estimatedFiveHourTotalTokens)
        XCTAssertNil(switched.samples[1].estimatedWeeklyTotalTokens)
        XCTAssertEqual(estimated.samples[2].tokensSincePreviousSample, 1_000)
        XCTAssertEqual(estimated.samples[2].estimatedFiveHourTotalTokens, 20_000)
        XCTAssertEqual(estimated.samples[2].estimatedWeeklyTotalTokens, 20_000)

        let restored = QuotaCapacityHistory(samples: [
            QuotaCapacitySample(
                capturedAt: firstDate,
                accountID: "first",
                fiveHourUsedPercent: 10,
                weeklyUsedPercent: 20,
                fiveHourResetAt: firstAccount.fiveHourWindow?.resetsAt,
                weeklyResetAt: firstAccount.weeklyWindow?.resetsAt,
                tokensSincePreviousSample: 0,
                estimatedFiveHourTotalTokens: nil,
                estimatedWeeklyTotalTokens: nil
            ),
            QuotaCapacitySample(
                capturedAt: secondDate,
                accountID: "second",
                fiveHourUsedPercent: 11,
                weeklyUsedPercent: 31,
                fiveHourResetAt: secondAccount.fiveHourWindow?.resetsAt,
                weeklyResetAt: secondAccount.weeklyWindow?.resetsAt,
                tokensSincePreviousSample: 1_000_000,
                estimatedFiveHourTotalTokens: 100_000_000,
                estimatedWeeklyTotalTokens: 100_000_000
            )
        ])
        XCTAssertEqual(restored.samples[1].tokensSincePreviousSample, 0)
        XCTAssertNil(restored.samples[1].estimatedFiveHourTotalTokens)
        XCTAssertNil(restored.samples[1].estimatedWeeklyTotalTokens)
    }

    private func checkQuotaResetNotificationsDetectWindowRefreshes() {
        let reset = Date(timeIntervalSince1970: 1_781_388_300)
        let now = reset.addingTimeInterval(60)
        var previous = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 99, weeklyUsed: 20, now: reset)
        previous.weeklyWindow?.resetsAt = now.addingTimeInterval(3_600)
        var current = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 1, weeklyUsed: 20, now: reset.addingTimeInterval(5 * 3_600))
        current.weeklyWindow?.resetsAt = previous.weeklyWindow?.resetsAt

        let notifications = QuotaResetNotifications.refreshedQuotaWindows(
            previous: [previous],
            current: [current],
            now: now,
            language: .english
        )

        XCTAssertEqual(notifications.count, 1)
        XCTAssertTrue(notifications[0].id.contains("fiveHour"))
        XCTAssertEqual(notifications[0].title, "5-hour quota refreshed")

        let futureAdjustment = QuotaResetNotifications.refreshedQuotaWindows(
            previous: [current],
            current: [{
                var account = current
                account.fiveHourWindow?.resetsAt = now.addingTimeInterval(6 * 3_600)
                return account
            }()],
            now: now,
            language: .english
        )
        XCTAssertTrue(futureAdjustment.isEmpty)
    }

    private func checkTaskCompletionNotificationsDetectNewlyFinishedTasks() {
        let startedAt = Date(timeIntervalSince1970: 1_783_666_800)
        let completedAt = startedAt.addingTimeInterval(75)
        let previous = AgentTask(
            id: "turn-1",
            sessionID: "session-1",
            title: "Build task center",
            projectName: "AgentBar",
            cwd: "/repo/AgentBar",
            startedAt: startedAt,
            completedAt: nil,
            lastActivityAt: startedAt.addingTimeInterval(60),
            tokens: TokenTotals(input: 80, cachedInput: 0, output: 20, reasoningOutput: 0, total: 100),
            estimatedCostUSD: Decimal(string: "0.02"),
            models: ["gpt-5.6-terra"],
            terminalState: nil
        )
        var completed = previous
        completed.completedAt = completedAt
        completed.lastActivityAt = completedAt
        completed.terminalState = .completed

        let notifications = TaskCompletionNotifications.newlyCompleted(
            previous: [previous],
            current: [completed],
            completedAfter: startedAt,
            language: .english
        )

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.title, "Codex task completed")
        XCTAssertTrue(notifications.first?.body.contains("Build task center") == true)
        XCTAssertTrue(TaskCompletionNotifications.newlyCompleted(
            previous: [completed],
            current: [completed],
            completedAfter: startedAt,
            language: .english
        ).isEmpty)
    }

    @MainActor
    private func checkAccessTokenExpiryNotificationSettingPersists() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertFalse(settings.accessTokenExpiryNotificationsEnabled)
        settings.accessTokenExpiryNotificationsEnabled = true

        XCTAssertTrue(SettingsStore(defaults: defaults).accessTokenExpiryNotificationsEnabled)
    }

    private func checkAccessTokenExpiryReminderPlanning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var account = testAccount(id: "acct-a", name: "a@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: now)
        let expiry = now.addingTimeInterval(2 * 86_400)
        account.accessTokenExpiresAt = expiry

        let plan = AccessTokenExpiryReminderPlanner.plan(
            accounts: [account],
            registeredExpirations: [:],
            enabled: true,
            now: now,
            language: .english
        )

        XCTAssertEqual(plan.reminders.first?.deliveryDate, expiry.addingTimeInterval(-86_400))
        XCTAssertEqual(plan.reminders.first?.title, "Codex access token expires soon")
        XCTAssertEqual(plan.registrations[account.id], expiry.timeIntervalSince1970)
        XCTAssertTrue(AccessTokenExpiryReminderPlanner.plan(
            accounts: [account],
            registeredExpirations: plan.registrations,
            enabled: true,
            now: now,
            language: .english
        ).reminders.isEmpty)

        var urgent = account
        urgent.accessTokenExpiresAt = now.addingTimeInterval(12 * 3_600)
        let urgentPlan = AccessTokenExpiryReminderPlanner.plan(
            accounts: [urgent],
            registeredExpirations: [:],
            enabled: true,
            now: now,
            language: .english
        )
        XCTAssertEqual(urgentPlan.reminders.first?.deliveryDate, now)

        var expired = account
        expired.accessTokenExpiresAt = now.addingTimeInterval(-1)
        var claude = account
        claude.id = "claude"
        claude.service = .claudeCode
        XCTAssertTrue(AccessTokenExpiryReminderPlanner.plan(
            accounts: [expired, claude],
            registeredExpirations: [:],
            enabled: true,
            now: now,
            language: .english
        ).reminders.isEmpty)

        let changedPlan = AccessTokenExpiryReminderPlanner.plan(
            accounts: [account],
            registeredExpirations: [account.id: expiry.addingTimeInterval(-1).timeIntervalSince1970],
            enabled: true,
            now: now,
            language: .english
        )
        XCTAssertEqual(changedPlan.reminders.count, 1)
        XCTAssertEqual(changedPlan.notificationIDsToRemove, ["access-token-expiry-acct-a"])

        let disabledPlan = AccessTokenExpiryReminderPlanner.plan(
            accounts: [account],
            registeredExpirations: plan.registrations,
            enabled: false,
            now: now,
            language: .english
        )
        XCTAssertTrue(disabledPlan.reminders.isEmpty)
        XCTAssertTrue(disabledPlan.registrations.isEmpty)
        XCTAssertEqual(disabledPlan.notificationIDsToRemove, ["access-token-expiry-acct-a"])
    }

    @MainActor
    private func checkUsageStoreReconcilesAccessTokenExpiryReminders() async {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.accessTokenExpiryNotificationsEnabled = true
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let account = {
            var account = testAccount(id: "acct-a", name: "a@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: now)
            account.accessTokenExpiresAt = now.addingTimeInterval(2 * 86_400)
            return account
        }()
        let recorder = AccessTokenExpiryReconciliationRecorder()
        let store = UsageStore(
            settings: settings,
            codexUsageSynchronizer: { .success },
            codexUsageReader: {
                UsageSnapshot(
                    service: .codex,
                    status: .live,
                    accounts: [account],
                    points: [],
                    securityNotes: [],
                    refreshedAt: now,
                    pricingFingerprint: Pricing.fingerprint
                )
            },
            claudeUsageReader: {
                UsageSnapshot(
                    service: .claudeCode,
                    status: .unavailable,
                    accounts: [],
                    points: [],
                    securityNotes: [],
                    refreshedAt: now,
                    pricingFingerprint: Pricing.fingerprint
                )
            },
            accessTokenExpiryReminderReconciler: { accounts, enabled, language in
                recorder.record(accounts: accounts, enabled: enabled, language: language)
            }
        )
        store.start()
        defer { store.stop() }

        store.refresh(force: true)
        for _ in 0..<100 where recorder.events.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(recorder.events.last?.accountIDs, ["acct-a"])
        XCTAssertEqual(recorder.events.last?.enabled, true)
        XCTAssertEqual(recorder.events.last?.language, .english)

        settings.accessTokenExpiryNotificationsEnabled = false
        for _ in 0..<100 where recorder.events.last?.enabled != false {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(recorder.events.last?.enabled, false)
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

    private func checkTodayAndYesterdayChartBarsUseHourlyBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-13T22:00:00Z")!
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let points = [
            UsagePoint(service: .codex, model: "codex-local", date: todayStart.addingTimeInterval(2 * 3_600 + 60), tokens: TokenTotals(input: 10, cachedInput: 0, output: 2, reasoningOutput: 0, total: 12), estimatedCostUSD: Decimal(string: "0.001")),
            UsagePoint(service: .claudeCode, model: "claude-local", date: todayStart.addingTimeInterval(23 * 3_600 + 30), tokens: TokenTotals(input: 20, cachedInput: 0, output: 4, reasoningOutput: 0, total: 24), estimatedCostUSD: Decimal(string: "0.002")),
            UsagePoint(service: .codex, model: "codex-local", date: yesterdayStart.addingTimeInterval(7 * 3_600), tokens: TokenTotals(input: 30, cachedInput: 0, output: 6, reasoningOutput: 0, total: 36), estimatedCostUSD: Decimal(string: "0.003"))
        ]

        let todayBars = UsageStatistics.hourlyBars(points: points, range: .today, now: now, calendar: calendar)
        let yesterdayBars = UsageStatistics.hourlyBars(points: points, range: .yesterday, now: now, calendar: calendar)

        XCTAssertEqual(todayBars.count, 23)
        XCTAssertEqual(todayBars.first?.day, todayStart)
        XCTAssertEqual(todayBars.last?.day, todayStart.addingTimeInterval(22 * 3_600))
        XCTAssertEqual(todayBars[2].codexTokens, 12)
        XCTAssertEqual(todayBars.map { $0.codexTokens + $0.claudeTokens }.reduce(0, +), 12)
        XCTAssertEqual(yesterdayBars.count, 24)
        XCTAssertEqual(yesterdayBars[7].codexTokens, 36)
    }

    private func checkYearActivityBarsFillLast365Days() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-13T22:00:00Z")!
        let start = calendar.date(byAdding: .day, value: -364, to: calendar.startOfDay(for: now))!
        let excluded = calendar.date(byAdding: .day, value: -1, to: start)!
        let points = [
            UsagePoint(service: .codex, model: "codex-local", date: now, tokens: TokenTotals(input: 10, cachedInput: 0, output: 2, reasoningOutput: 0, total: 12), estimatedCostUSD: Decimal(string: "0.001")),
            UsagePoint(service: .claudeCode, model: "claude-local", date: start.addingTimeInterval(60), tokens: TokenTotals(input: 30, cachedInput: 0, output: 6, reasoningOutput: 0, total: 36), estimatedCostUSD: Decimal(string: "0.002")),
            UsagePoint(service: .codex, model: "old", date: excluded, tokens: TokenTotals(input: 99, cachedInput: 0, output: 1, reasoningOutput: 0, total: 100), estimatedCostUSD: nil)
        ]

        let bars = UsageStatistics.yearActivityBars(points: points, now: now, calendar: calendar)

        XCTAssertEqual(bars.count, 365)
        XCTAssertEqual(bars.first?.day, start)
        XCTAssertEqual(bars.last?.day, calendar.startOfDay(for: now))
        XCTAssertEqual(bars.first?.claudeTokens, 36)
        XCTAssertEqual(bars.last?.codexTokens, 12)
        XCTAssertEqual(bars.map { $0.codexTokens + $0.claudeTokens }.reduce(0, +), 48)
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

    @MainActor
    private func checkUsageStoreStatisticsCachesInvalidateWhenInputsChange() {
        let now = Date()
        let older = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let store = UsageStore(codexUsageSynchronizer: { .success })
        store.applyTestData(points: [
            UsagePoint(service: .codex, model: "gpt-5", date: now, tokens: TokenTotals(input: 10, cachedInput: 0, output: 0, reasoningOutput: 0, total: 10), estimatedCostUSD: nil),
            UsagePoint(service: .codex, model: "gpt-5", date: older, tokens: TokenTotals(input: 20, cachedInput: 0, output: 0, reasoningOutput: 0, total: 20), estimatedCostUSD: nil)
        ])

        XCTAssertEqual(store.summary.totalTokens, 10)
        store.selectedRange = .last7Days
        XCTAssertEqual(store.summary.totalTokens, 30)

        store.applyTestData(points: [
            UsagePoint(service: .codex, model: "gpt-5", date: now, tokens: TokenTotals(input: 5, cachedInput: 0, output: 0, reasoningOutput: 0, total: 5), estimatedCostUSD: nil)
        ])
        XCTAssertEqual(store.summary.totalTokens, 5)
        XCTAssertEqual(store.selectedRangePoints.map(\.tokens.total), [5])
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
        XCTAssertEqual(UsageRangeProjection.filteredPoints(points: points, range: .last7Days, now: now, calendar: calendar).map(\.tokens.total).reduce(0, +), 150)
    }

    private func checkUsageRangeChartTitlesMatchSelectedInterval() {
        XCTAssertEqual(UsageRange.today.chartTitle(.chinese), "今日用量")
        XCTAssertEqual(UsageRange.yesterday.chartTitle(.chinese), "昨日用量")
        XCTAssertEqual(UsageRange.thisWeek.chartTitle(.chinese), "本周用量")
        XCTAssertEqual(UsageRange.thisMonth.chartTitle(.chinese), "本月用量")
        XCTAssertEqual(UsageRange.thisYear.chartTitle(.chinese), "本年用量")
        XCTAssertEqual(UsageRange.last7Days.chartTitle(.chinese), "连续7日用量")
        XCTAssertEqual(UsageRange.last30Days.chartTitle(.chinese), "连续30日用量")
        XCTAssertEqual(UsageRange.last7Days.chartTitle(.english), "Rolling 7-day usage")
    }

    private func checkChangePercentFormattingShowsDirectionAndMissingBaseline() {
        XCTAssertEqual(DisplayFormatters.changePercentString(50), "↑ 50.0%")
        XCTAssertEqual(DisplayFormatters.changePercentString(-25.26), "↓ 25.3%")
        XCTAssertEqual(DisplayFormatters.changePercentString(0), "0.0%")
        XCTAssertEqual(DisplayFormatters.changePercentString(nil), "--")
    }

    private func checkCostFormattingUsesTwoDecimals() {
        XCTAssertEqual(DisplayFormatters.costString(Decimal(string: "467.35428875")!), "$467.35")
        XCTAssertEqual(DisplayFormatters.costString(Decimal(string: "0.1")!), "$0.10")
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

    @MainActor
    private func checkAccountDataDisplayScopesUsagePoints() {
        let suiteName = "AgentBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        var account = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 20, weeklyUsed: 40, now: Date())
        account.isActive = true
        let store = UsageStore(settings: settings)
        let codexPoint = UsagePoint(service: .codex, model: "codex-local", date: Date(), tokens: TokenTotals(input: 10, cachedInput: 0, output: 0, reasoningOutput: 0, total: 10), estimatedCostUSD: nil)
        let claudePoint = UsagePoint(service: .claudeCode, model: "claude-local", date: Date(), tokens: TokenTotals(input: 20, cachedInput: 0, output: 0, reasoningOutput: 0, total: 20), estimatedCostUSD: nil)

        store.applyTestData(accounts: [account], points: [codexPoint, claudePoint])

        XCTAssertEqual(store.usageDataDisplayPoints.map(\.tokens.total), [10])
        settings.showAggregatedAccountData = true
        XCTAssertEqual(store.usageDataDisplayPoints.map(\.tokens.total), [10, 20])
        XCTAssertTrue(SettingsStore(defaults: defaults).showAggregatedAccountData)
    }

    private func checkEnglishCompactTokenFormattingUsesEnglishUnits() {
        XCTAssertEqual(DisplayFormatters.compactTokenString(63_229_600, language: .english), "63.2296 mil")
        XCTAssertEqual(DisplayFormatters.compactTokenString(6_322_960_000, language: .english), "6.3230 bil")
    }

    private func checkDailyUsageBarTooltipIncludesDateAndUsageDetails() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let bar = DailyUsageBar(
            day: day,
            codexTokens: 1_500_000,
            claudeTokens: 2_000_000,
            codexCostUSD: Decimal(string: "0.011")!,
            claudeCostUSD: Decimal(string: "0.022")!
        )

        let tooltip = bar.tooltipText(language: .english)

        XCTAssertTrue(tooltip.contains("Jun 13, 2026"))
        XCTAssertTrue(tooltip.contains("Codex: 1.5000 mil Tokens · $0.01"))
        XCTAssertTrue(tooltip.contains("Claude: 2.0000 mil Tokens · $0.02"))
        XCTAssertTrue(tooltip.contains("Total: 3.5000 mil Tokens · $0.03"))
    }

    private func checkAccountMetadataShowsResetActivityAndAccountType() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let account = testAccount(id: "active", name: "active@example.com", fiveHourUsed: 1, weeklyUsed: 8, now: now)

        XCTAssertTrue(account.accountTypeLine(language: .english).contains("Account type: TEAM"))
        XCTAssertTrue(account.lastActivityLine(language: .english).contains("Last activity:"))
        XCTAssertTrue(account.fiveHourWindow?.resetLine(language: .english).contains("Reset:") == true)
    }

    private func checkExpiredResetCreditUsesExpiredLabel() {
        let credits = UsageResetCredits(
            availableCount: 1,
            resets: [UsageResetCredit(expiresAt: .distantPast)]
        )

        XCTAssertTrue(credits.expirationLines(language: .english)[0].hasSuffix("(Expired)"))
        XCTAssertTrue(credits.expirationLines(language: .chinese)[0].hasSuffix("(已过期)"))
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

    private func checkCodexAccountSwitcherRejectsMismatchedSnapshot() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let accountDir = temp.appending(path: ".codex/accounts")
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        let registry = accountDir.appending(path: "registry.json")
        try """
        {"schema_version":3,"active_account_key":"acct-a","accounts":[{"account_key":"acct-a","email":"a@example.com","chatgpt_account_id":"workspace-a"},{"account_key":"acct-b","email":"b@example.com","chatgpt_account_id":"workspace-b"}]}
        """.data(using: .utf8)!.write(to: registry)
        let activeAuth = temp.appending(path: ".codex/auth.json")
        try "old active auth".data(using: .utf8)!.write(to: activeAuth)
        try authJSON(accessToken: "wrong-token", accountID: "workspace-a", email: "a@example.com")
            .data(using: .utf8)!
            .write(to: accountDir.appending(path: "acct-b.auth.json"))

        XCTAssertThrowsError(try CodexAccountSwitcher(homeDirectory: temp).switchActiveAccount(accountID: "acct-b")) { error in
            XCTAssertEqual(error as? AccountActionError, .mismatchedAccountSnapshot)
        }
        XCTAssertEqual(try String(contentsOf: activeAuth, encoding: .utf8), "old active auth")
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

    private func codexReader(
        homeDirectory: URL,
        now: Date = Date(timeIntervalSince1970: 1_781_385_600)
    ) -> CodexUsageReader {
        CodexUsageReader(homeDirectory: homeDirectory, now: { now })
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

    private func authJSON(accessToken: String, accountID: String, email: String) -> String {
        #"{"auth_mode":"chatgpt","tokens":{"access_token":"\#(accessToken)","account_id":"\#(accountID)","id_token":"\#(idToken(email: email))"}}"#
    }

    private func idToken(email: String) -> String {
        "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(#"{"email":"\#(email)"}"#))."
    }

    private func accessToken(expiry: Date) -> String {
        "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(#"{"exp":\#(Int(expiry.timeIntervalSince1970))}"#))."
    }

    private func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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

    @MainActor
    private final class AccessTokenExpiryReconciliationRecorder {
        struct Event {
            var accountIDs: [String]
            var enabled: Bool
            var language: AppLanguage
        }

        private(set) var events: [Event] = []

        func record(accounts: [UsageAccount], enabled: Bool, language: AppLanguage) {
            events.append(Event(accountIDs: accounts.map(\.id), enabled: enabled, language: language))
        }
    }

    private final class UsageAPIRequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        private var count = 0
        private var recordedAccountIDs: [String] = []

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

        var accountIDs: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedAccountIDs
        }

        func record(_ request: URLRequest) {
            lock.lock()
            self.request = request
            count += 1
            if let accountID = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") {
                recordedAccountIDs.append(accountID)
            }
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
