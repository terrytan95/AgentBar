import XCTest
@testable import AgentBar

final class SystemGuardianTests: XCTestCase {
    func testCommandRedactionRemovesCredentialValues() {
        let redacted = GuardianProcessRow.redactedCommand(
            #"codex --access_token=secret-token --cookie "session-cookie" --normal value"#
        )

        XCTAssertTrue(redacted.contains("codex"))
        XCTAssertTrue(redacted.contains("--normal value"))
        XCTAssertFalse(redacted.contains("secret-token"))
        XCTAssertFalse(redacted.contains("session-cookie"))
        XCTAssertTrue(redacted.contains("[redacted]"))
    }

    func testMissingSessionStoreIsWarningAndNonDestructive() {
        let health = SessionStoreHealth.missing(path: "/tmp/missing-sessions")

        XCTAssertEqual(health.severity, .warning)
        XCTAssertFalse(health.exists)
        XCTAssertEqual(health.totalBytes, 0)
        XCTAssertTrue(health.summary.contains("not found"))
    }

    func testSessionStoreClassifiesLargeStoresAsCritical() {
        let health = SessionStoreHealth.classify(
            path: "/tmp/sessions",
            totalBytes: 1_200_000_000,
            jsonlFileCount: 80,
            recentFileCount: 2,
            oldFileCount: 60,
            largeFileCount: 12,
            latestWriteAt: Date(timeIntervalSince1970: 1_781_388_300)
        )

        XCTAssertEqual(health.severity, .critical)
        XCTAssertTrue(health.summary.contains("storage pressure"))
    }

    func testGuardianRecommendationFlagsHighCPUAndSessionPressure() {
        let snapshot = SystemGuardianSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_781_388_300),
            processes: [
                GuardianProcessRow(pid: 10, name: "Codex", cpuPercent: 42, memoryBytes: 100_000_000, command: "codex app-server")
            ],
            sessionStore: SessionStoreHealth.classify(
                path: "/tmp/sessions",
                totalBytes: 400_000_000,
                jsonlFileCount: 100,
                recentFileCount: 1,
                oldFileCount: 70,
                largeFileCount: 1,
                latestWriteAt: nil
            ),
            dataSourceHealth: DataSourceHealthSummary(rows: [], liveCount: 1, issueCount: 1)
        )

        let recommendations = GuardianRecommendationEngine.recommendations(for: snapshot)

        XCTAssertTrue(recommendations.contains { $0.title.contains("CPU") && $0.severity == .warning })
        XCTAssertTrue(recommendations.contains { $0.title.contains("session") && $0.requiresConfirmation })
        XCTAssertTrue(recommendations.contains { $0.title.contains("data source") && !$0.requiresConfirmation })
        XCTAssertEqual(GuardianRecommendationEngine.overallSeverity(for: snapshot), .critical)
    }
}
