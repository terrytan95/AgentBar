import XCTest
@testable import AgentBar

final class ClaudeDiscoveryTests: XCTestCase {

    func testClaudeDiscoveryCoverage() throws {
        try checkClaudeDiscoveryReportsUnavailableWhenNoClaudeCodeSourceExists()
        try checkClaudeDiscoveryDoesNotCreatePlaceholderWhenCliDirectoryHasNoSafeUsageSource()
        try checkClaudeDiscoveryReportsAuthenticationFailure()
        try checkClaudeDiscoveryReadsLocalSessionUsage()
        try checkClaudeDiscoveryUsesCurrentClaudePricingAndBuildsLocalAccount()
    }
    private func checkClaudeDiscoveryReportsUnavailableWhenNoClaudeCodeSourceExists() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let snapshot = ClaudeUsageReader.discover(homeDirectory: root)

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertTrue(snapshot.securityNotes.joined(separator: " ").localizedCaseInsensitiveContains("not found") == true)
    }

    private func checkClaudeDiscoveryDoesNotCreatePlaceholderWhenCliDirectoryHasNoSafeUsageSource() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let claudeDirectory = root.appending(path: ".claude")
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let snapshot = ClaudeUsageReader.discover(homeDirectory: root)

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertTrue(snapshot.securityNotes.joined(separator: " ").localizedCaseInsensitiveContains("usage records"))
    }

    private func checkClaudeDiscoveryReadsLocalSessionUsage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let projectDirectory = root.appending(path: ".claude/projects/example")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let transcript = """
        {"type":"user","sessionId":"session-1","timestamp":"2026-07-26T12:00:00.000Z","cwd":"/tmp/example"}
        {"type":"assistant","sessionId":"session-1","timestamp":"2026-07-26T12:00:01.000Z","cwd":"/tmp/example","message":{"id":"message-1","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40}}}
        """
        try Data(transcript.utf8).write(to: projectDirectory.appending(path: "session-1.jsonl"))

        let snapshot = ClaudeUsageReader.discover(homeDirectory: root)

        XCTAssertEqual(snapshot.status, .live)
        XCTAssertEqual(snapshot.points.count, 1)
        let point = try XCTUnwrap(snapshot.points.first)
        XCTAssertEqual(point.model, "claude-sonnet-4-6")
        XCTAssertEqual(point.tokens, TokenTotals(input: 60, cachedInput: 30, output: 40, reasoningOutput: 0, total: 100))
        XCTAssertEqual(point.sessionID, "session-1")
        XCTAssertEqual(point.projectName, "example")
        XCTAssertEqual(point.cwd, "/tmp/example")
        XCTAssertEqual(point.estimatedCostUSD, Decimal(string: "0.000714"))
    }

    private func checkClaudeDiscoveryReportsAuthenticationFailure() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let projectDirectory = root.appending(path: ".claude/projects/example")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let transcript = """
        {"type":"assistant","timestamp":"2026-07-26T12:00:01.000Z","error":"authentication_failed","message":{"id":"message-1","model":"<synthetic>","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
        """
        try Data(transcript.utf8).write(to: projectDirectory.appending(path: "session-1.jsonl"))

        let snapshot = ClaudeUsageReader.discover(homeDirectory: root)

        XCTAssertEqual(snapshot.status, .needsAuthorization)
        XCTAssertTrue(snapshot.securityNotes.joined(separator: " ").localizedCaseInsensitiveContains("not signed in"))
    }

    private func checkClaudeDiscoveryUsesCurrentClaudePricingAndBuildsLocalAccount() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let projectDirectory = root.appending(path: ".claude/projects/example")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let transcript = """
        {"type":"assistant","sessionId":"session-1","timestamp":"2026-07-26T12:00:01.000Z","cwd":"/tmp/example","message":{"id":"message-1","model":"claude-sonnet-5","usage":{"input_tokens":1000000,"cache_creation_input_tokens":2000000,"cache_read_input_tokens":1000000,"output_tokens":1000000,"cache_creation":{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":1000000},"inference_geo":"us","server_tool_use":{"web_search_requests":2}}}}
        """
        try Data(transcript.utf8).write(to: projectDirectory.appending(path: "session-1.jsonl"))

        let snapshot = ClaudeUsageReader.discover(homeDirectory: root)

        let point = try XCTUnwrap(snapshot.points.first)
        XCTAssertEqual(point.estimatedCostUSD, Decimal(string: "20.59"))
        XCTAssertEqual(
            Pricing.cost(
                model: "claude-opus-4-8",
                input: 1_000_000,
                output: 1_000_000,
                cacheRead: 0,
                cacheCreation: 0,
                speed: "fast",
                at: point.date
            ),
            Decimal(60)
        )
        let account = try XCTUnwrap(snapshot.accounts.first)
        XCTAssertEqual(account.service, .claudeCode)
        XCTAssertEqual(account.tokens, point.tokens)
        XCTAssertEqual(account.estimatedCostUSD, point.estimatedCostUSD)
    }
}
