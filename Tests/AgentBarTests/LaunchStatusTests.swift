import XCTest
@testable import AgentBar

final class LaunchStatusTests: XCTestCase {
    func testLaunchStatusAccountRowsIncludeAllAccounts() {
        let accounts = (0..<8).map { index in
            UsageAccount(
                id: "account-\(index)",
                service: .codex,
                displayName: "user\(index)@example.com",
                username: "user\(index)@example.com",
                maskedEmail: "u***@example.com",
                plan: "team",
                sourceDescription: "Test registry",
                status: .live,
                fiveHourWindow: nil,
                weeklyWindow: nil,
                tokens: .zero,
                estimatedCostUSD: nil,
                lastUpdated: nil
            )
        }

        XCTAssertEqual(LaunchStatusAccountList.accountsToDisplay(from: accounts).count, 8)
    }
}
