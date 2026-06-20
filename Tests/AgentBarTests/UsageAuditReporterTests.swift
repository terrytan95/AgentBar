import XCTest
@testable import AgentBar

final class UsageAuditReporterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_388_300)

    func testReportIncludesTopServiceModelSpikeBudgetAndSourceHealth() {
        let points = baselinePoints() + [
            point(model: "gpt-5", daysAgo: 0, input: 3_000, cached: 200, output: 2_000, reasoning: 1_000, cost: "1.25")
        ]
        let health = DataSourceHealthSummary(
            rows: [
                DataSourceHealthSummary.Row(service: .codex, status: .live, note: nil, refreshedAt: now),
                DataSourceHealthSummary.Row(service: .claudeCode, status: .unavailable, note: "No source", refreshedAt: now)
            ],
            liveCount: 1,
            issueCount: 1
        )

        let report = UsageAuditReporter.makeReport(
            points: points,
            range: .today,
            budgetStatus: BudgetStatus(tokenUsageFraction: 0.86, costUsageFraction: nil, tokenSeverity: .warning, costSeverity: .ok),
            dataSourceHealth: health,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(report.title.contains("Daily"))
        XCTAssertTrue(report.body.contains("6,200 tokens"))
        XCTAssertTrue(report.body.contains("Top service: Codex"))
        XCTAssertTrue(report.body.contains("Top model: gpt-5"))
        XCTAssertTrue(report.body.contains("spike"))
        XCTAssertTrue(report.body.contains("Budget: warning"))
        XCTAssertTrue(report.body.contains("Data sources: 1 live, 1 issue"))
        XCTAssertTrue(report.body.contains("local parsed session logs"))
    }

    func testExportRowsFilterRangeAndSerializeCSVWithEscaping() throws {
        let rows = UsageAuditReporter.exportRows(
            points: [
                point(model: "gpt,5", daysAgo: 0, input: 1, cached: 2, output: 3, reasoning: 4, cost: "0.10"),
                point(model: "old", daysAgo: 3, input: 10, cached: 0, output: 0, reasoning: 0, cost: nil)
            ],
            range: .today,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 1)
        let csv = UsageAuditReporter.serialize(rows: rows, format: .csv)
        XCTAssertTrue(csv.contains("date,service,model,input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens,total_tokens,estimated_cost_usd"))
        XCTAssertTrue(csv.contains(#""gpt,5""#))
        XCTAssertTrue(csv.contains(",1,2,3,4,10,0.1"))
    }

    func testJSONSerializationUsesNullForMissingCost() throws {
        let rows = UsageAuditReporter.exportRows(
            points: [point(model: "gpt-5", daysAgo: 0, input: 1, cached: 0, output: 1, reasoning: 0, cost: nil)],
            range: .today,
            now: now,
            calendar: calendar
        )

        let json = UsageAuditReporter.serialize(rows: rows, format: .json)
        XCTAssertTrue(json.contains(#""estimated_cost_usd" : null"#) || json.contains(#""estimated_cost_usd": null"#))
        XCTAssertTrue(json.contains(#""model" : "gpt-5""#) || json.contains(#""model": "gpt-5""#))
    }

    func testPreviousRangeComparisonUsesComparableWindow() {
        let points = [
            point(model: "gpt-5", daysAgo: 0, input: 80, cached: 0, output: 20, reasoning: 0, cost: nil),
            point(model: "gpt-5", daysAgo: 1, input: 20, cached: 0, output: 20, reasoning: 0, cost: nil)
        ]

        let comparison = UsageAuditReporter.rangeComparison(
            points: points,
            range: .today,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(comparison?.currentTokens, 100)
        XCTAssertEqual(comparison?.previousTokens, 40)
        XCTAssertEqual(comparison?.tokenPercentChange ?? 0, 150, accuracy: 0.001)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func baselinePoints() -> [UsagePoint] {
        (1...7).map { offset in
            point(model: "gpt-4.1", daysAgo: offset, input: 300, cached: 0, output: 100, reasoning: 0, cost: nil)
        }
    }

    private func point(
        model: String,
        daysAgo: Int,
        input: Int,
        cached: Int,
        output: Int,
        reasoning: Int,
        cost: String?
    ) -> UsagePoint {
        UsagePoint(
            service: .codex,
            model: model,
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
            tokens: TokenTotals(input: input, cachedInput: cached, output: output, reasoningOutput: reasoning, total: input + cached + output + reasoning),
            estimatedCostUSD: cost.map { NSDecimalNumber(string: $0).decimalValue }
        )
    }
}
