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
            contentHeight: 180,
            mainScreenMaxY: 1_440
        )

        XCTAssertEqual(frame, CGRect(x: 112, y: 646, width: 336, height: 180))

        let narrowerFrame = CodexSidebarQuotaOverlayController.panelFrame(
            codexBounds: CGRect(x: 100, y: 80, width: 800, height: 800),
            contentHeight: 180,
            mainScreenMaxY: 1_440
        )
        XCTAssertEqual(narrowerFrame?.width, 256)
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
