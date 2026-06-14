import XCTest
@testable import AgentBar

final class PopoverLayoutTests: XCTestCase {
    func testPopoverHeightGrowsWithAccountCount() {
        let fourAccounts = PopoverLayout.height(accountCount: 4, sourceCount: 1)
        let eightAccounts = PopoverLayout.height(accountCount: 8, sourceCount: 1)

        XCTAssertGreaterThan(eightAccounts, fourAccounts)
    }

    func testPopoverHeightIsCappedForLargeAccountCounts() {
        let manyAccounts = PopoverLayout.height(accountCount: 32, sourceCount: 2)

        XCTAssertEqual(manyAccounts, PopoverLayout.maximumHeight)
    }
}
