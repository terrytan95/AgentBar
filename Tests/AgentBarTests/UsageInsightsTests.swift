import XCTest
@testable import AgentBar

final class UsageInsightsTests: XCTestCase {
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
}
