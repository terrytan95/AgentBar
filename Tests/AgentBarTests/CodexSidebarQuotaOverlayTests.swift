import XCTest
@testable import AgentBar

final class CodexSidebarQuotaOverlayTests: XCTestCase {
    func testCardStateShowsEveryAvailableWindowInOrder() {
        let account = account(fiveHour: window(.fiveHour), weekly: window(.weekly))

        XCTAssertEqual(CodexSidebarQuotaCardState(account: account).windows.map(\.kind), [.fiveHour, .weekly])
    }

    func testCardStateOmitsMissingFiveHourWindow() {
        let account = account(fiveHour: nil, weekly: window(.weekly))

        XCTAssertEqual(CodexSidebarQuotaCardState(account: account).windows.map(\.kind), [.weekly])
    }

    func testCardStateClassifiesCredentialExpiry() {
        let expiry = Date(timeIntervalSince1970: 2_000)
        let state = CodexSidebarQuotaCardState(account: account(credentialExpiresAt: expiry))

        XCTAssertEqual(state.credentialState(at: Date(timeIntervalSince1970: 1_000)), .valid(expiry))
        XCTAssertEqual(state.credentialState(at: expiry), .expired(expiry))
    }

    func testPanelFrameTracksSidebarWidthAndUsesEqualMargins() {
        let frame = CodexSidebarQuotaOverlayController.panelFrame(
            codexBounds: CGRect(x: 100, y: 80, width: 1_200, height: 800),
            sidebarWidth: 301,
            contentHeight: 180,
            mainScreenMaxY: 1_440
        )

        XCTAssertEqual(frame, CGRect(x: 112, y: 646, width: 277, height: 180))

        let narrowerFrame = CodexSidebarQuotaOverlayController.panelFrame(
            codexBounds: CGRect(x: 100, y: 80, width: 800, height: 800),
            contentHeight: 180,
            mainScreenMaxY: 1_440
        )
        XCTAssertEqual(narrowerFrame?.width, 256)
    }

    func testSidebarWidthUsesLeftEdgeAccessibilityGeometry() {
        let codexBounds = CGRect(x: 100, y: 80, width: 1_200, height: 800)

        let width = CodexSidebarQuotaOverlayController.sidebarWidth(
            candidates: [
                CGRect(x: 100, y: 120, width: 301, height: 73),
                CGRect(x: 108, y: 700, width: 270, height: 31),
                CGRect(x: 500, y: 500, width: 420, height: 200)
            ],
            codexBounds: codexBounds
        )

        XCTAssertEqual(width, 301)
    }

    func testPanelFrameMovesAboveAccountMenuWithEqualMargins() {
        let frame = CodexSidebarQuotaOverlayController.panelFrame(
            codexBounds: CGRect(x: 100, y: 80, width: 1_200, height: 800),
            sidebarWidth: 301,
            accountMenuBounds: CGRect(x: 120, y: 600, width: 320, height: 240),
            contentHeight: 180,
            mainScreenMaxY: 1_440
        )

        XCTAssertEqual(frame, CGRect(x: 112, y: 852, width: 277, height: 180))
    }

    func testAccountMenuBoundsSelectsBottomSidebarPopup() {
        let codexBounds = CGRect(x: 100, y: 80, width: 1_200, height: 800)
        let expectedMenu = CGRect(x: 100, y: 540, width: 360, height: 260)

        let menu = CodexSidebarQuotaOverlayController.accountMenuBounds(
            candidates: [
                CGRect(x: 500, y: 500, width: 300, height: 250),
                CGRect(x: 100, y: 120, width: 360, height: 300),
                expectedMenu
            ],
            codexBounds: codexBounds
        )

        XCTAssertEqual(menu, expectedMenu)
    }

    func testPanelFrameHidesForSmallCodexWindow() {
        XCTAssertNil(CodexSidebarQuotaOverlayController.panelFrame(
            codexBounds: CGRect(x: 0, y: 0, width: 719, height: 800),
            contentHeight: 180,
            mainScreenMaxY: 1_440
        ))
    }

    private func window(_ kind: UsageWindow.Kind) -> UsageWindow {
        UsageWindow(
            kind: kind,
            usedPercent: 25,
            windowMinutes: kind == .fiveHour ? 300 : 10_080,
            resetsAt: Date(timeIntervalSince1970: 3_000)
        )
    }

    private func account(
        fiveHour: UsageWindow? = nil,
        weekly: UsageWindow? = nil,
        credentialExpiresAt: Date? = nil
    ) -> UsageAccount {
        UsageAccount(
            id: "acct",
            service: .codex,
            displayName: "Codex Account",
            username: nil,
            maskedEmail: nil,
            plan: "pro",
            sourceDescription: "Test",
            status: .live,
            fiveHourWindow: fiveHour,
            weeklyWindow: weekly,
            credentialExpiresAt: credentialExpiresAt,
            tokens: .zero,
            estimatedCostUSD: nil,
            lastUpdated: nil,
            isActive: true
        )
    }
}
