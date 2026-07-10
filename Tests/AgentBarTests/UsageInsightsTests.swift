import XCTest
@testable import AgentBar

final class UsageInsightsTests: XCTestCase {
    func testOpenTaskBecomesWaitingAfterActivityStops() {
        let startedAt = Date(timeIntervalSince1970: 1_783_666_800)
        let task = AgentTask(
            id: "turn-1",
            sessionID: "session-1",
            title: "Await approval",
            projectName: "AgentBar",
            cwd: "/repo/AgentBar",
            startedAt: startedAt,
            completedAt: nil,
            lastActivityAt: startedAt.addingTimeInterval(10),
            tokens: .zero,
            estimatedCostUSD: nil,
            models: [],
            terminalState: nil
        )

        XCTAssertEqual(task.state(at: startedAt.addingTimeInterval(60)), .working)
        XCTAssertEqual(task.state(at: startedAt.addingTimeInterval(299)), .working)
        XCTAssertEqual(task.state(at: startedAt.addingTimeInterval(311)), .waiting)
    }

    func testProjectUsageAggregatesRepositoryModelsTrendAndBudget() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_783_666_800)
        let today = now.addingTimeInterval(-60)
        let previousDay = now.addingTimeInterval(-86_400)
        let points = [
            projectPoint(path: "/repo/AgentBar", model: "gpt-5.6-terra", date: today, tokens: 700, cost: "0.70"),
            projectPoint(path: "/repo/AgentBar", model: "gpt-5.6-luna", date: today, tokens: 500, cost: "0.30"),
            projectPoint(path: "/repo/AgentBar", model: "gpt-5.6-terra", date: previousDay, tokens: 600, cost: "0.50"),
            projectPoint(path: "/repo/Other", model: "gpt-5.6-luna", date: today, tokens: 200, cost: "0.10")
        ]
        let budget = ProjectBudget(id: "/repo/AgentBar", dailyTokenLimit: 1_000, dailyCostLimitUSD: 2)

        let projects = ProjectUsageAnalytics.summaries(
            points: points,
            range: .today,
            budgets: [budget],
            now: now,
            calendar: calendar
        )
        let agentBar = try XCTUnwrap(projects.first(where: { $0.id == "/repo/AgentBar" }))

        XCTAssertEqual(agentBar.name, "AgentBar")
        XCTAssertEqual(agentBar.summary.totalTokens, 1_200)
        XCTAssertEqual(agentBar.summary.estimatedCostUSD, Decimal(string: "1.00"))
        XCTAssertEqual(agentBar.models.map(\.model), ["gpt-5.6-terra", "gpt-5.6-luna"])
        XCTAssertEqual(try XCTUnwrap(agentBar.periodChange.tokenPercent), 100, accuracy: 0.001)
        XCTAssertEqual(agentBar.budgetStatus.tokenSeverity, .critical)
    }

    func testRepositoryIdentityResolvesGitRootAndRejectsPlainFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = root.appending(path: "AgentBar")
        let nested = repository.appending(path: "Sources/AgentBar")
        let plainFolder = root.appending(path: "scratch")
        try FileManager.default.createDirectory(at: repository.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plainFolder, withIntermediateDirectories: true)

        XCTAssertEqual(RepositoryIdentityResolver.repositoryPath(for: nested.path), repository.path)
        XCTAssertNil(RepositoryIdentityResolver.repositoryPath(for: plainFolder.path))
    }

    @MainActor
    func testProjectBudgetsPersistPerRepository() {
        let suiteName = "ProjectBudgets-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.updateProjectBudget(ProjectBudget(
            id: "/repo/AgentBar",
            dailyTokenLimit: 10_000,
            weeklyTokenLimit: 50_000,
            dailyCostLimitUSD: 5,
            weeklyCostLimitUSD: 20
        ))

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.projectBudget(for: "/repo/AgentBar").dailyTokenLimit, 10_000)
        XCTAssertEqual(reloaded.projectBudget(for: "/repo/AgentBar").weeklyCostLimitUSD, 20)
    }

    func testDashboardOverviewUsesStatisticsInsights() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        var active = account(id: "active", name: "active@example.com", fiveHourUsed: 96, weeklyUsed: 20, now: now, active: true)
        active.workspaces = [UsageWorkspace(name: "Active Workspace", workspaceID: "active-123456")]
        let better = account(id: "better", name: "better@example.com", fiveHourUsed: 20, weeklyUsed: 10, now: now, active: false)
        var locked = account(id: "locked", name: "locked@example.com", fiveHourUsed: 10, weeklyUsed: 20, now: now, active: false)
        locked.loginWarning = .forcedLogout
        locked.workspaces = [UsageWorkspace(name: "Team Workspace", workspaceID: "workspace-123456")]
        let calendar = Calendar(identifier: .gregorian)
        let baseline = (2...7).map { dayOffset in
            UsagePoint(
                service: .codex,
                model: "gpt-5",
                date: calendar.date(byAdding: .day, value: -dayOffset, to: now)!,
                tokens: TokenTotals(input: 500, cachedInput: 0, output: 500, reasoningOutput: 0, total: 1_000),
                estimatedCostUSD: nil
            )
        }
        let points = baseline + [
            point(total: 6_000, minutesAgo: 5, now: now, model: "gpt-5", sessionID: "session-a", sessionTitle: "Fix dashboard", projectName: "AgentBar", cost: "0.30"),
            point(total: 1_000, minutesAgo: 25, now: now, model: "gpt-5-mini", sessionID: "session-b", sessionTitle: "Audit release", projectName: "Other", cost: "0.10")
        ]

        let pressure = UsageInsights.quotaPressure(
            accounts: [active, better, locked],
            points: points,
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            now: now
        )
        let topUsage = UsageInsights.topUsage(
            points: points,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(pressure.activeAccount?.id, "active")
        XCTAssertEqual(pressure.recommendedAccount?.id, "better")
        XCTAssertTrue(pressure.shouldTriggerRotation)
        XCTAssertEqual(topUsage.sessions.first?.label, "Fix dashboard")
        XCTAssertEqual(topUsage.sessions.first?.tokens, 6_000)
    }

    func testQuotaPressureRecommendationPrioritizesFiveHourThenWeeklyRemaining() {
        let now = Date(timeIntervalSince1970: 1_781_388_300)
        let active = account(id: "active", name: "active@example.com", fiveHourUsed: 98, weeklyUsed: 20, now: now, active: true)
        let moreWeekly = account(id: "more-weekly", name: "weekly@example.com", fiveHourUsed: 35, weeklyUsed: 5, now: now, active: false)
        let sameFiveHourLessWeekly = account(id: "less-weekly", name: "less-weekly@example.com", fiveHourUsed: 20, weeklyUsed: 70, now: now, active: false)
        let moreFiveHour = account(id: "more-five-hour", name: "five@example.com", fiveHourUsed: 20, weeklyUsed: 40, now: now, active: false)

        let pressure = UsageInsights.quotaPressure(
            accounts: [active, moreWeekly, sameFiveHourLessWeekly, moreFiveHour],
            points: [],
            rotationThresholdRemainingPercent: 10,
            autoRotationEnabled: true,
            now: now
        )

        XCTAssertEqual(pressure.recommendedAccount?.id, "more-five-hour")
    }

    private func account(
        id: String,
        name: String,
        fiveHourUsed: Double,
        weeklyUsed: Double,
        now: Date,
        active: Bool
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
            fiveHourWindow: UsageWindow(kind: .fiveHour, usedPercent: fiveHourUsed, windowMinutes: 300, resetsAt: now.addingTimeInterval(4 * 60 * 60)),
            weeklyWindow: UsageWindow(kind: .weekly, usedPercent: weeklyUsed, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60)),
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
        model: String,
        sessionID: String,
        sessionTitle: String,
        projectName: String,
        cost: String
    ) -> UsagePoint {
        UsagePoint(
            service: .codex,
            model: model,
            date: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
            tokens: TokenTotals(input: total / 2, cachedInput: 0, output: total / 2, reasoningOutput: 0, total: total),
            estimatedCostUSD: NSDecimalNumber(string: cost).decimalValue,
            sessionID: sessionID,
            sessionTitle: sessionTitle,
            projectName: projectName
        )
    }

    private func projectPoint(path: String, model: String, date: Date, tokens: Int, cost: String) -> UsagePoint {
        UsagePoint(
            service: .codex,
            model: model,
            date: date,
            tokens: TokenTotals(input: tokens, cachedInput: 0, output: 0, reasoningOutput: 0, total: tokens),
            estimatedCostUSD: Decimal(string: cost),
            projectName: URL(fileURLWithPath: path).lastPathComponent,
            cwd: path,
            repositoryPath: path
        )
    }
}
