import XCTest
@testable import AgentBar

final class UsageAuditReporterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_781_388_300)

    func testUsageAuditReporterCoverage() throws {
        try checkExportRowsFilterRangeAndSerializeCSVWithEscaping()
        try checkJSONSerializationUsesNullForMissingCost()
        try checkAuditSnapshotPreparesResizeDataOnce()
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

    private func checkAuditSnapshotPreparesResizeDataOnce() throws {
        let older = UsagePoint(
            service: .codex,
            model: "gpt-5",
            date: now.addingTimeInterval(-60),
            tokens: TokenTotals(input: 100, cachedInput: 40, output: 20, reasoningOutput: 10, total: 170),
            estimatedCostUSD: Decimal(string: "0.10"),
            sessionID: "thread-a",
            sessionTitle: "Resize Audit",
            projectName: "AgentBar"
        )
        let newer = UsagePoint(
            service: .codex,
            model: "gpt-5",
            date: now,
            tokens: TokenTotals(input: 180, cachedInput: 60, output: 40, reasoningOutput: 20, total: 300),
            estimatedCostUSD: Decimal(string: "0.20"),
            sessionID: "thread-a",
            sessionTitle: "Resize Audit",
            projectName: "AgentBar"
        )

        let snapshot = AuditUsageSnapshot.make(
            points: [older, newer],
            range: .all,
            customStart: nil,
            customEnd: nil,
            sortColumn: .tokens,
            sortAscending: false
        )

        XCTAssertEqual(snapshot.rangePoints.map(\.callID), [newer.callID, older.callID])
        XCTAssertEqual(snapshot.sortedCalls.map(\.tokens.total), [300, 170])
        XCTAssertEqual(snapshot.callIDs, snapshot.rangePoints.map(\.callID))
        XCTAssertEqual(snapshot.composition.total, 470)
        XCTAssertEqual(NSDecimalNumber(decimal: try XCTUnwrap(snapshot.totalCost)).stringValue, "0.3")

        let thread = try XCTUnwrap(snapshot.threadRows.first)
        XCTAssertEqual(snapshot.threadRows.count, 1)
        XCTAssertEqual(thread.calls.map(\.callID), [newer.callID, older.callID])
        XCTAssertEqual(thread.tokens.total, 470)
        XCTAssertEqual(thread.duration, "1m 0s")
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
