import XCTest
@testable import AgentBar

final class ClaudeDiscoveryTests: XCTestCase {

    func testClaudeDiscoveryCoverage() throws {
        try checkClaudeDiscoveryReportsUnavailableWhenNoClaudeCodeSourceExists()
        try checkClaudeDiscoveryDoesNotCreatePlaceholderWhenCliDirectoryHasNoSafeUsageSource()
        try checkClaudeDiscoveryReadsLocalSessionUsage()
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
}
