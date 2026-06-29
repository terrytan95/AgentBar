import SwiftUI
import XCTest
@testable import AgentBar

final class PopoverLayoutTests: XCTestCase {

    @MainActor
    func testPopoverLayoutCoverage() throws {
        checkPointingHandCursorModifierIsAvailableForInteractiveViews()
        checkPopoverMaximumHeightCanUseScreenHeight()
        checkPopoverHeightGrowsWithAccountCount()
        checkPopoverHeightIsCappedForLargeAccountCounts()
        checkPopoverUsesCompactMenuBarSizing()
        checkPopoverHeightDoesNotUseUserPreferenceOverride()
        checkPopoverHeightCanUsePreferredHeightWithinBounds()
        checkAuditKpiGridHeightMatchesColumnCount()
    }
    @MainActor
    private func checkPointingHandCursorModifierIsAvailableForInteractiveViews() {
        _ = Text("Interactive").pointingHandCursor()
    }

    private func checkPopoverMaximumHeightCanUseScreenHeight() {
        XCTAssertEqual(PopoverLayout.maximumHeight(forScreenHeight: 1_440), 1_392)
        XCTAssertEqual(PopoverLayout.maximumHeight(forScreenHeight: 300), PopoverLayout.minimumHeight)
        XCTAssertEqual(PopoverLayout.maximumHeight(forScreenHeight: nil), PopoverLayout.maximumHeight)
    }

    private func checkPopoverHeightGrowsWithAccountCount() {
        let fourAccounts = PopoverLayout.height(accountCount: 4, sourceCount: 1)
        let eightAccounts = PopoverLayout.height(accountCount: 8, sourceCount: 1)

        XCTAssertGreaterThan(eightAccounts, fourAccounts)
    }

    private func checkPopoverHeightIsCappedForLargeAccountCounts() {
        let manyAccounts = PopoverLayout.height(accountCount: 32, sourceCount: 2)

        XCTAssertEqual(manyAccounts, PopoverLayout.defaultHeight)
    }

    private func checkPopoverUsesCompactMenuBarSizing() {
        XCTAssertLessThanOrEqual(PopoverLayout.width, 390)
        XCTAssertLessThanOrEqual(PopoverLayout.defaultHeight, 740)
    }

    private func checkPopoverHeightDoesNotUseUserPreferenceOverride() {
        XCTAssertEqual(
            PopoverLayout.height(accountCount: 32, sourceCount: 2),
            PopoverLayout.defaultHeight
        )
    }

    private func checkPopoverHeightCanUsePreferredHeightWithinBounds() {
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 560), 560)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 100), PopoverLayout.minimumHeight)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 1_400), PopoverLayout.maximumHeight)
        XCTAssertEqual(PopoverLayout.height(accountCount: 32, sourceCount: 2, preferredHeight: 1_400, maximumHeight: 1_392), 1_392)
    }

    private func checkAuditKpiGridHeightMatchesColumnCount() {
        XCTAssertEqual(AuditView.kpiGridColumns(for: 1_000), 6)
        XCTAssertEqual(AuditView.kpiGridHeight(for: 1_000), 96)
        XCTAssertEqual(AuditView.kpiGridColumns(for: 900), 3)
        XCTAssertEqual(AuditView.kpiGridHeight(for: 900), 204)
    }
}
