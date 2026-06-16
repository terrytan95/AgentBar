import SwiftUI
import XCTest
@testable import AgentBar

final class PopoverLayoutTests: XCTestCase {
    @MainActor
    func testPointingHandCursorModifierIsAvailableForInteractiveViews() {
        _ = Text("Interactive").pointingHandCursor()
    }

    func testResizablePanelHeightTracksAbsolutePointerDelta() {
        let resize = PanelResizeBounds(minHeight: 240, maxHeight: 720)

        XCTAssertEqual(resize.height(startHeight: 360, translation: 75), 435)
        XCTAssertEqual(resize.height(startHeight: 360, translation: -80), 280)
    }

    func testPopoverResizeDragUsesStableScreenCoordinates() {
        let resize = PopoverResizeDrag(bounds: PanelResizeBounds(minHeight: 420, maxHeight: 860))

        XCTAssertEqual(resize.height(startHeight: 560, startScreenY: 700, currentScreenY: 620), 640)
        XCTAssertEqual(resize.height(startHeight: 560, startScreenY: 700, currentScreenY: 760), 500)
    }

    func testPopoverMaximumHeightCanUseScreenHeight() {
        XCTAssertEqual(PopoverLayout.maximumHeight(forScreenHeight: 1_440), 1_392)
        XCTAssertEqual(PopoverLayout.maximumHeight(forScreenHeight: 300), PopoverLayout.minimumHeight)
        XCTAssertEqual(PopoverLayout.maximumHeight(forScreenHeight: nil), PopoverLayout.maximumHeight)
    }

    func testPopoverResizeDragFiltersSubpixelIntermediateUpdates() {
        XCTAssertFalse(PopoverResizeDrag.shouldEmit(previousHeight: 560, nextHeight: 561.5, isFinal: false))
        XCTAssertTrue(PopoverResizeDrag.shouldEmit(previousHeight: 560, nextHeight: 562, isFinal: false))
        XCTAssertTrue(PopoverResizeDrag.shouldEmit(previousHeight: 560, nextHeight: 560.2, isFinal: true))
    }

    func testPopoverResizeDragCanUseCustomEmissionThreshold() {
        XCTAssertFalse(
            PopoverResizeDrag.shouldEmit(
                previousHeight: 560,
                nextHeight: 560.2,
                isFinal: false,
                minimumDelta: 0.5
            )
        )
        XCTAssertTrue(
            PopoverResizeDrag.shouldEmit(
                previousHeight: 560,
                nextHeight: 560.6,
                isFinal: false,
                minimumDelta: 0.5
            )
        )
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

    func testPopoverHeightDoesNotUseUserPreferenceOverride() {
        XCTAssertEqual(
            PopoverLayout.height(accountCount: 32, sourceCount: 2),
            PopoverLayout.defaultHeight
        )
    }

    func testPopoverHeightCanUsePreferredHeightWithinBounds() {
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 560), 560)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 100), PopoverLayout.minimumHeight)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 1_400), PopoverLayout.maximumHeight)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 1_400, maximumHeight: 1_392), 1_392)
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
