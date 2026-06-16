import XCTest
@testable import AgentBar

final class LocalizationTests: XCTestCase {
    func testQuitAppLabelIsLocalizedForPopoverFooter() {
        XCTAssertEqual(L.text("quit_app", .english), "Quit")
        XCTAssertEqual(L.text("quit_app", .chinese), "退出")
    }
}
