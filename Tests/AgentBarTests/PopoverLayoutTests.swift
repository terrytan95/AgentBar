import XCTest
@testable import AgentBar

final class PopoverLayoutTests: XCTestCase {
    func testResizablePanelHeightTracksAbsolutePointerDelta() {
        let resize = PanelResizeBounds(minHeight: 240, maxHeight: 720)

        XCTAssertEqual(resize.height(startHeight: 360, translation: 75), 435)
        XCTAssertEqual(resize.height(startHeight: 360, translation: -80), 280)
    }

    func testResizablePanelHeightClampsAtBounds() {
        let resize = PanelResizeBounds(minHeight: 240, maxHeight: 720)

        XCTAssertEqual(resize.height(startHeight: 360, translation: -500), 240)
        XCTAssertEqual(resize.height(startHeight: 360, translation: 500), 720)
    }

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
