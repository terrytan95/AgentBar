import Foundation
import XCTest
@testable import AgentBar

final class XAIUsageReaderTests: XCTestCase {
    func testReadsGrokCLISubscriptionUsage() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authDirectory = home.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: authDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let auth = """
        {
          "https://auth.x.ai::test-client": {
            "key": "test-token",
            "user_id": "user-123",
            "team_id": "team-456",
            "expires_at": "2026-08-01T00:00:00Z"
          }
        }
        """
        try Data(auth.utf8).write(to: authDirectory.appendingPathComponent("auth.json"))

        let sessionDirectory = authDirectory
            .appendingPathComponent("sessions/project/session-123", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        try Data(#"{"current_model_id":"grok-4.5","generated_title":"Fix usage","reasoning_effort":"high","info":{"id":"session-123","cwd":"/tmp/project"}}"#.utf8)
            .write(to: sessionDirectory.appendingPathComponent("summary.json"))
        try Data(#"{"method":"_x.ai/session/update","timestamp":1775000100,"params":{"update":{"sessionUpdate":"turn_completed","usage":{"inputTokens":1200,"cachedReadTokens":800,"outputTokens":300,"reasoningTokens":100,"totalTokens":1500,"costUsdTicks":1250000000,"modelUsage":{"grok-4.5-build":{"inputTokens":1200,"cachedReadTokens":800,"outputTokens":300,"reasoningTokens":100,"totalTokens":1500,"costUsdTicks":1250000000}}}}}}"#.utf8)
            .write(to: sessionDirectory.appendingPathComponent("updates.jsonl"))

        let reader = XAIUsageReader(
            homeDirectory: home,
            now: { Date(timeIntervalSince1970: 1_775_000_000) },
            client: { request, _ in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-userid"), "user-123")
                if request.url?.path.hasSuffix("/settings") == true {
                    return (200, Data(#"{"subscription_tier_display":"SuperGrok"}"#.utf8))
                }
                let billing = """
                {
                  "config": {
                    "creditUsagePercent": 42.5,
                    "currentPeriod": {
                      "type": "USAGE_PERIOD_TYPE_WEEKLY",
                      "start": "2026-07-27T00:00:00Z",
                      "end": "2026-08-03T00:00:00Z"
                    },
                    "onDemandCap": {"val": 500},
                    "onDemandUsed": {"val": 120},
                    "prepaidBalance": {"val": 750}
                  }
                }
                """
                return (200, Data(billing.utf8))
            },
            sessionRefresher: { _ in false }
        )

        let result = await reader.read()
        let snapshot = try XCTUnwrap(result)
        let account = try XCTUnwrap(snapshot.accounts.first)
        XCTAssertEqual(snapshot.status, .live)
        XCTAssertEqual(account.displayName, "Grok")
        XCTAssertEqual(account.plan, "SuperGrok")
        XCTAssertEqual(account.weeklyWindow?.usedPercent, 42.5)
        XCTAssertEqual(account.weeklyWindow?.windowMinutes, 7 * 24 * 60)
        XCTAssertEqual(account.grokSubscriptionUsage?.prepaidBalanceUSD, Decimal(string: "7.5"))
        XCTAssertEqual(account.grokSubscriptionUsage?.onDemandUsedUSD, Decimal(string: "1.2"))
        XCTAssertEqual(account.grokSubscriptionUsage?.onDemandCapUSD, Decimal(string: "5"))
        XCTAssertEqual(account.tokens.total, 1_500)
        XCTAssertEqual(account.estimatedCostUSD, Decimal(string: "0.125"))
        let point = try XCTUnwrap(snapshot.points.first)
        XCTAssertEqual(point.model, "grok-4.5-build")
        XCTAssertEqual(point.tokens, TokenTotals(input: 1_200, cachedInput: 800, output: 300, reasoningOutput: 100, total: 1_500))
        XCTAssertEqual(point.estimatedCostUSD, Decimal(string: "0.125"))
        XCTAssertEqual(point.sessionID, "session-123")
        XCTAssertEqual(point.sessionTitle, "Fix usage")
        XCTAssertEqual(point.cwd, "/tmp/project")
        XCTAssertEqual(point.reasoningEffort, "high")
    }
}
