import XCTest
@testable import AgentBar

final class ClaudeDiscoveryTests: XCTestCase {

    func testClaudeDiscoveryCoverage() throws {
        try checkClaudeDiscoveryReportsUnavailableWhenNoClaudeCodeSourceExists()
        try checkClaudeDiscoveryDoesNotCreatePlaceholderWhenCliDirectoryHasNoSafeUsageSource()
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

        XCTAssertEqual(snapshot.status, .needsAuthorization)
        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertTrue(snapshot.securityNotes.joined(separator: " ").localizedCaseInsensitiveContains("authorization"))
    }
}
