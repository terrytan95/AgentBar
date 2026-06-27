import XCTest
@testable import AgentBar

final class UsageInsightsTests: XCTestCase {
    func testCurrentLimitSummaryFindsMostConstrainedAccountAndWindowMinimums() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let summary = UsageInsights.currentLimitSummary(accounts: [
            account(id: "active", name: "active@example.com", fiveHourUsed: 92, weeklyUsed: 40, now: now, active: true),
            account(id: "weekly-low", name: "weekly@example.com", fiveHourUsed: 20, weeklyUsed: 88, now: now, active: false),
            account(id: "healthy", name: "healthy@example.com", fiveHourUsed: 10, weeklyUsed: 15, now: now, active: false)
        ])

        XCTAssertEqual(summary.accountCount, 3)
        XCTAssertEqual(summary.lowestFiveHourRemaining, 8)
        XCTAssertEqual(summary.lowestWeeklyRemaining, 12)
        XCTAssertEqual(summary.mostConstrainedAccount?.id, "active")
    }

    func testQuotaPressureWarnsWhenActiveAccountCanExhaustSoonAndRecommendsBestAlternative() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let reset = now.addingTimeInterval(2 * 60 * 60)
        let active = account(id: "active", name: "active@example.com", fiveHourUsed: 92, weeklyUsed: 20, now: now, active: true, fiveHourReset: reset)
        let better = account(id: "better", name: "better@example.com", fiveHourUsed: 18, weeklyUsed: 10, now: now, active: false, fiveHourReset: reset)
        let worse = account(id: "worse", name: "worse@example.com", fiveHourUsed: 86, weeklyUsed: 15, now: now, active: false, fiveHourReset: reset)

        let pressure = UsageInsights.quotaPressure(
            accounts: [active, better, worse],
            points: [
                point(total: 3_000, minutesAgo: 60, now: now),
                point(total: 3_200, minutesAgo: 30, now: now),
                point(total: 3_200, minutesAgo: 5, now: now)
            ],
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            now: now
        )

        XCTAssertEqual(pressure.severity, .critical)
        XCTAssertEqual(pressure.activeAccount?.id, "active")
        XCTAssertEqual(pressure.recommendedAccount?.id, "better")
        XCTAssertTrue(pressure.shouldTriggerRotation)
        XCTAssertNotNil(pressure.projectedFiveHourExhaustion)
    }

    func testUsageAnomaliesHighlightLargeDailyAndModelSpikes() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let calendar = Calendar(identifier: .gregorian)
        let baselineDays = (2...7).flatMap { dayOffset in
            [
                UsagePoint(
                    service: .codex,
                    model: "codex-local",
                    date: calendar.date(byAdding: .day, value: -dayOffset, to: now)!,
                    tokens: TokenTotals(input: 500, cachedInput: 0, output: 500, reasoningOutput: 0, total: 1_000),
                    estimatedCostUSD: nil
                )
            ]
        }
        let anomalies = UsageInsights.usageAnomalies(
            points: baselineDays + [
                UsagePoint(
                    service: .codex,
                    model: "codex-local",
                    date: now,
                    tokens: TokenTotals(input: 3_000, cachedInput: 0, output: 3_000, reasoningOutput: 0, total: 6_000),
                    estimatedCostUSD: Decimal(string: "4.25")
                )
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(anomalies.contains { $0.kind == .dailyTokens && $0.multiple >= 3 })
        XCTAssertTrue(anomalies.contains { $0.kind == .modelTokens && $0.label == "codex-local" })
        XCTAssertEqual(anomalies.first { $0.kind == .dailyTokens }?.estimatedCostUSD, Decimal(string: "4.25"))
    }

    func testBudgetStatusWarnsForDailyTokenAndCostThresholds() {
        let status = UsageInsights.budgetStatus(
            summary: UsageSummary(
                totalTokens: 9_200,
                inputTokens: 6_000,
                outputTokens: 3_200,
                reasoningTokens: 0,
                estimatedCostUSD: Decimal(string: "18.50"),
                serviceBreakdown: [.codex: 9_200],
                modelBreakdown: ["codex-local": 9_200],
                dailyBars: [],
                pricingFingerprint: Pricing.fingerprint
            ),
            dailyTokenBudget: 10_000,
            dailyCostBudgetUSD: 20
        )

        XCTAssertEqual(status.tokenSeverity, .warning)
        XCTAssertEqual(status.costSeverity, .warning)
        XCTAssertEqual(status.tokenUsageFraction ?? 0, 0.92, accuracy: 0.001)
        XCTAssertEqual(status.costUsageFraction ?? 0, 0.925, accuracy: 0.001)
    }

    func testDataSourceHealthSummarizesLiveAndUnavailableSnapshots() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let health = UsageInsights.dataSourceHealth(snapshots: [
            .codex: UsageSnapshot(service: .codex, status: .live, accounts: [], points: [], securityNotes: [], refreshedAt: now, pricingFingerprint: Pricing.fingerprint),
            .claudeCode: UsageSnapshot.empty(service: .claudeCode, status: .unavailable, note: "No Claude data")
        ])

        XCTAssertEqual(health.liveCount, 1)
        XCTAssertEqual(health.issueCount, 1)
        XCTAssertEqual(health.rows.map(\.service), [.claudeCode, .codex])
    }

    func testQuotaETAUsesRecentTokenVelocity() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let account = account(id: "active", name: "active@example.com", fiveHourUsed: 90, weeklyUsed: 20, now: now, active: true)
        let eta = UsageInsights.quotaETA(
            account: account,
            points: [
                point(total: 400, minutesAgo: 10, now: now),
                point(total: 200, minutesAgo: 35, now: now),
                point(total: 600, minutesAgo: 55, now: now)
            ],
            now: now
        )

        XCTAssertEqual(try XCTUnwrap(eta.windows.first { $0.minutes == 15 }?.tokens), 400)
        XCTAssertEqual(try XCTUnwrap(eta.windows.first { $0.minutes == 30 }?.minutesUntilFiveHourExhaustion), 10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(eta.windows.first { $0.minutes == 60 }?.minutesUntilFiveHourExhaustion), 6.667, accuracy: 0.001)
    }

    func testWorkSessionPlanUsesRecentVelocityAndRecommendedAccount() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let active = account(id: "active", name: "active@example.com", fiveHourUsed: 90, weeklyUsed: 20, now: now, active: true)
        let better = account(id: "better", name: "better@example.com", fiveHourUsed: 20, weeklyUsed: 10, now: now, active: false)
        let pressure = UsageInsights.quotaPressure(
            accounts: [active, better],
            points: [point(total: 400, minutesAgo: 10, now: now)],
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            now: now
        )

        let plan = try XCTUnwrap(UsageInsights.workSessionPlan(
            activeAccount: active,
            points: [
                point(total: 400, minutesAgo: 10, now: now),
                point(total: 200, minutesAgo: 35, now: now),
                point(total: 600, minutesAgo: 55, now: now)
            ],
            pressure: pressure,
            now: now
        ))

        XCTAssertEqual(plan.activeAccount.id, "active")
        XCTAssertEqual(plan.recommendedAccount?.id, "better")
        XCTAssertEqual(plan.bestWindow.minutes, 30)
        XCTAssertEqual(plan.minutesUntilFiveHourExhaustion ?? 0, 10, accuracy: 0.001)
    }

    func testTopUsageBreakdownGroupsSessionsProjectsDaysAndModels() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let top = UsageInsights.topUsage(
            points: [
                point(total: 1_000, minutesAgo: 10, now: now, model: "gpt-5", sessionID: "session-a", sessionTitle: "Fix high CPU usage", projectName: "AgentBar", cost: "0.30"),
                point(total: 500, minutesAgo: 20, now: now, model: "gpt-5", sessionID: "session-a", sessionTitle: "Fix high CPU usage", projectName: "AgentBar", cost: "0.10"),
                point(total: 800, minutesAgo: 30, now: now, model: "gpt-5-mini", sessionID: "session-b", projectName: "Other", cost: "0.05")
            ],
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(top.sessions.first?.label, "Fix high CPU usage")
        XCTAssertEqual(top.sessions.first?.tokens, 1_500)
        XCTAssertEqual(top.sessions.first?.estimatedCostUSD, Decimal(string: "0.40"))
        XCTAssertEqual(top.sessions.first?.lastUsedAt, now.addingTimeInterval(-10 * 60))
        XCTAssertEqual(top.projects.first?.label, "AgentBar")
        XCTAssertEqual(top.models.first?.label, "gpt-5")
        XCTAssertEqual(top.days.first?.tokens, 2_300)
    }

    func testSessionDrilldownAggregatesSelectedSessionByModelAndProject() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let detail = try XCTUnwrap(UsageInsights.sessionDrilldown(
            for: "session-a",
            points: [
                point(total: 1_000, minutesAgo: 10, now: now, model: "gpt-5", sessionID: "session-a", sessionTitle: "Fix high CPU usage", projectName: "AgentBar", cost: "0.30"),
                point(total: 500, minutesAgo: 20, now: now, model: "gpt-5-mini", sessionID: "session-a", sessionTitle: "Fix high CPU usage", projectName: "AgentBar", cost: "0.10"),
                point(total: 800, minutesAgo: 30, now: now, model: "gpt-5", sessionID: "session-b", projectName: "Other", cost: "0.20")
            ]
        ))

        XCTAssertEqual(detail.title, "Fix high CPU usage")
        XCTAssertEqual(detail.projectName, "AgentBar")
        XCTAssertEqual(detail.totalTokens, 1_500)
        XCTAssertEqual(detail.estimatedCostUSD, Decimal(string: "0.40"))
        XCTAssertEqual(detail.models.map(\.label), ["gpt-5", "gpt-5-mini"])
        XCTAssertEqual(detail.models.map(\.tokens), [1_000, 500])
    }

    func testAccountHealthCenterCombinesAccountAndDataSourceProblems() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        var locked = account(id: "locked", name: "locked@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: now, active: false)
        locked.loginWarning = .forcedLogout
        locked.workspaces = [UsageWorkspace(name: "Team Workspace", workspaceID: "workspace-123456")]
        let health = UsageInsights.accountHealthCenter(
            accounts: [locked],
            dataSourceHealth: DataSourceHealthSummary(
                rows: [
                    DataSourceHealthSummary.Row(
                        service: .codex,
                        status: .needsAuthorization,
                        note: "Codex usage API sync failed",
                        refreshedAt: now
                    )
                ],
                liveCount: 0,
                issueCount: 1
            ),
            language: .english
        )

        XCTAssertEqual(health.rows.map(\.kind), [.login, .dataSource])
        XCTAssertEqual(health.rows.first?.accountID, "locked")
        XCTAssertTrue(health.rows.first?.title.contains("locked@example.com") == true)
        XCTAssertEqual(health.rows.first?.workspaceLines, ["Workspace: Team Workspace · workspac"])
        XCTAssertTrue(health.rows.last?.detail.contains("Codex usage API sync failed") == true)
    }

    func testRapidUsageAlertFlagsTenMinuteSpikeAgainstToday() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let alert = UsageInsights.rapidUsageAlert(
            points: [
                point(total: 6_000, minutesAgo: 5, now: now),
                point(total: 4_000, minutesAgo: 20, now: now)
            ],
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(try XCTUnwrap(alert).recentTokens, 6_000)
        XCTAssertEqual(try XCTUnwrap(alert).todayShare, 0.6, accuracy: 0.001)
    }

    func testDashboardOverviewProjectionComposesStatisticsInsights() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let active = account(id: "active", name: "active@example.com", fiveHourUsed: 96, weeklyUsed: 20, now: now, active: true)
        let better = account(id: "better", name: "better@example.com", fiveHourUsed: 20, weeklyUsed: 10, now: now, active: false)
        let points = [
            point(total: 6_000, minutesAgo: 5, now: now, model: "gpt-5", sessionID: "session-a", sessionTitle: "Fix dashboard", projectName: "AgentBar"),
            point(total: 1_000, minutesAgo: 25, now: now, model: "gpt-5-mini", sessionID: "session-b", sessionTitle: "Audit release", projectName: "AgentBar")
        ]

        let projection = UsageInsights.dashboardOverviewProjection(
            accounts: [active, better],
            points: points,
            snapshots: [
                .codex: UsageSnapshot(service: .codex, status: .live, accounts: [], points: [], securityNotes: [], refreshedAt: now, pricingFingerprint: Pricing.fingerprint),
                .claudeCode: UsageSnapshot.empty(service: .claudeCode, status: .unavailable, note: "No Claude data")
            ],
            selectedSessionLabel: nil,
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            language: .english,
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(projection.quotaPressure.activeAccount?.id, "active")
        XCTAssertEqual(projection.quotaPressure.recommendedAccount?.id, "better")
        XCTAssertTrue(projection.quotaPressure.shouldTriggerRotation)
        XCTAssertEqual(projection.quotaETA?.windows.first { $0.minutes == 15 }?.tokens, 6_000)
        XCTAssertEqual(projection.topUsage.sessions.first?.label, "Fix dashboard")
        XCTAssertEqual(projection.selectedSessionDetail?.title, "Fix dashboard")
        XCTAssertEqual(projection.rapidUsageAlert?.recentTokens, 6_000)
        XCTAssertEqual(projection.usageAnomalies.first?.kind, .dailyTokens)
        XCTAssertEqual(projection.dataSourceHealth.issueCount, 1)
        XCTAssertEqual(projection.accountHealthCenter.rows.map(\.kind), [.dataSource])
    }

    func testSwitchRecommendationExplainsWhyAlternativeIsBetter() throws {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let active = account(id: "active", name: "active@example.com", fiveHourUsed: 96, weeklyUsed: 20, now: now, active: true)
        let better = account(id: "better", name: "better@example.com", fiveHourUsed: 32, weeklyUsed: 10, now: now, active: false)
        let pressure = UsageInsights.quotaPressure(
            accounts: [active, better],
            points: [point(total: 4_000, minutesAgo: 15, now: now)],
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            now: now
        )

        XCTAssertTrue(try XCTUnwrap(pressure.recommendationReason).contains("active 5H 4%"))
        XCTAssertTrue(try XCTUnwrap(pressure.recommendationReason).contains("better@example.com 5H 68%"))
    }

    func testPopoverRecommendationSuggestsBestAccountWhenActiveQuotaIsCritical() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        var active = account(id: "active", name: "active@example.com", fiveHourUsed: 98, weeklyUsed: 30, now: now, active: true)
        active.workspaces = [UsageWorkspace(name: "Active Workspace", workspaceID: "active-123456")]
        var better = account(id: "better", name: "better@example.com", fiveHourUsed: 14, weeklyUsed: 20, now: now, active: false)
        better.workspaces = [UsageWorkspace(name: "Better Workspace", workspaceID: "better-123456")]
        let pressure = UsageInsights.quotaPressure(
            accounts: [active, better],
            points: [point(total: 4_000, minutesAgo: 15, now: now)],
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            now: now
        )

        let recommendation = PopoverActionRecommendation.make(
            pressure: pressure,
            dataSourceHealth: DataSourceHealthSummary(rows: [], liveCount: 1, issueCount: 0),
            language: .english
        )

        XCTAssertEqual(recommendation.severity, .critical)
        XCTAssertEqual(recommendation.action, .switchAccount("better"))
        XCTAssertEqual(recommendation.actionTitle, "Use better@example.com · Better Workspace · better-1")
        XCTAssertTrue(recommendation.title.contains("Switch"))
        XCTAssertTrue(recommendation.detail.contains("active@example.com · Active Workspace · active-1"))
        XCTAssertTrue(recommendation.detail.contains("5H 2%"))
    }

    func testPopoverRecommendationPrioritizesAndExplainsResetCreditAccount() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let active = account(id: "active", name: "active@example.com", fiveHourUsed: 98, weeklyUsed: 30, now: now, active: true)
        let resetCredit = account(id: "reset", name: "reset@example.com", fiveHourUsed: 45, weeklyUsed: 25, now: now, active: false, resetCredits: 2)
        let moreQuota = account(id: "more", name: "more@example.com", fiveHourUsed: 8, weeklyUsed: 10, now: now, active: false)
        let pressure = UsageInsights.quotaPressure(
            accounts: [active, resetCredit, moreQuota],
            points: [point(total: 4_000, minutesAgo: 15, now: now)],
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            now: now
        )

        let recommendation = PopoverActionRecommendation.make(
            pressure: pressure,
            dataSourceHealth: DataSourceHealthSummary(rows: [], liveCount: 1, issueCount: 0),
            language: .english
        )

        XCTAssertEqual(pressure.recommendedAccount?.id, "reset")
        XCTAssertEqual(recommendation.action, .switchAccount("reset"))
        XCTAssertTrue(recommendation.detail.contains("2 resets available"))
    }

    func testPopoverRecommendationAsksForRefreshWhenSourcesHaveIssuesAndNoActiveAccountExists() {
        let health = DataSourceHealthSummary(
            rows: [
                DataSourceHealthSummary.Row(
                    service: .codex,
                    status: .needsAuthorization,
                    note: "Auth missing",
                    refreshedAt: Date(timeIntervalSince1970: 1_781_388_300)
                )
            ],
            liveCount: 0,
            issueCount: 1
        )
        let pressure = QuotaPressureInsight(
            severity: .ok,
            activeAccount: nil,
            recommendedAccount: nil,
            projectedFiveHourExhaustion: nil,
            projectedWeeklyExhaustion: nil,
            shouldTriggerRotation: false
        )

        let recommendation = PopoverActionRecommendation.make(
            pressure: pressure,
            dataSourceHealth: health,
            language: .english
        )

        XCTAssertEqual(recommendation.severity, .warning)
        XCTAssertEqual(recommendation.action, .refresh)
        XCTAssertEqual(recommendation.actionTitle, "Refresh")
        XCTAssertTrue(recommendation.title.contains("Refresh"))
    }

    private func account(
        id: String,
        name: String,
        fiveHourUsed: Double,
        weeklyUsed: Double,
        now: Date,
        active: Bool,
        fiveHourReset: Date? = nil,
        resetCredits: Int = 0
    ) -> UsageAccount {
        UsageAccount(
            id: id,
            service: .codex,
            displayName: name,
            username: name,
            maskedEmail: name,
            plan: "team",
            sourceDescription: "test",
            status: .live,
            fiveHourWindow: UsageWindow(kind: .fiveHour, usedPercent: fiveHourUsed, windowMinutes: 300, resetsAt: fiveHourReset ?? now.addingTimeInterval(4 * 60 * 60)),
            weeklyWindow: UsageWindow(kind: .weekly, usedPercent: weeklyUsed, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60)),
            resetCredits: resetCredits > 0 ? UsageResetCredits(availableCount: resetCredits) : nil,
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: now,
            isActive: active
        )
    }

    private func point(
        total: Int,
        minutesAgo: Int,
        now: Date,
        model: String = "codex-local",
        sessionID: String? = nil,
        sessionTitle: String? = nil,
        projectName: String? = nil,
        cost: String? = nil
    ) -> UsagePoint {
        UsagePoint(
            service: .codex,
            model: model,
            date: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
            tokens: TokenTotals(input: total / 2, cachedInput: 0, output: total / 2, reasoningOutput: 0, total: total),
            estimatedCostUSD: cost.map { NSDecimalNumber(string: $0).decimalValue },
            sessionID: sessionID,
            sessionTitle: sessionTitle,
            projectName: projectName
        )
    }
}
