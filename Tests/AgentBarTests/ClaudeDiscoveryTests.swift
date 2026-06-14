import XCTest
@testable import AgentBar

final class ClaudeDiscoveryTests: XCTestCase {
    func testClaudeDiscoveryReportsUnavailableWhenNoClaudeCodeSourceExists() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let snapshot = ClaudeUsageReader.discover(homeDirectory: root)

        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertEqual(snapshot.accounts.first?.displayName, "Claude Code")
        XCTAssertTrue(snapshot.accounts.first?.sourceDescription.localizedCaseInsensitiveContains("not found") == true)
    }
}
