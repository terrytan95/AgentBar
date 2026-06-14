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

        XCTAssertEqual(manyAccounts, PopoverLayout.defaultHeight)
    }

    func testPopoverUsesCompactMenuBarSizing() {
        XCTAssertLessThanOrEqual(PopoverLayout.width, 390)
        XCTAssertLessThanOrEqual(PopoverLayout.defaultHeight, 740)
    }

    func testSettingsControlsCanReachTrailingSectionEdge() {
        XCTAssertEqual(SettingsControlLayout.leadingInset, SettingsControlLayout.trailingInset)
    }

    func testPopoverHeightCanUseUserPreferenceWithinBounds() {
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 560), 560)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 100), PopoverLayout.minimumHeight)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 1_400), PopoverLayout.maximumHeight)
    }

    func testChartTooltipTracksPointerAndClampsInsidePlot() {
        let placement = ChartTooltipPlacement.position(
            cursor: CGPoint(x: 180, y: 90),
            calloutSize: CGSize(width: 210, height: 94),
            plotSize: CGSize(width: 500, height: 260)
        )

        XCTAssertEqual(placement.x, 301)
        XCTAssertEqual(placement.y, 145)

        let clamped = ChartTooltipPlacement.position(
            cursor: CGPoint(x: 492, y: 252),
            calloutSize: CGSize(width: 210, height: 94),
            plotSize: CGSize(width: 500, height: 260)
        )

        XCTAssertEqual(clamped.x, 371)
        XCTAssertEqual(clamped.y, 197)
    }
}
