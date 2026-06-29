import XCTest
@testable import AgentBar

final class UsageAuditReporterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_388_300)

    func testUsageAuditReporterCoverage() throws {
        try checkExportRowsFilterRangeAndSerializeCSVWithEscaping()
        try checkJSONSerializationUsesNullForMissingCost()
    }

    private func checkExportRowsFilterRangeAndSerializeCSVWithEscaping() throws {
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

    private func checkJSONSerializationUsesNullForMissingCost() throws {
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

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
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
