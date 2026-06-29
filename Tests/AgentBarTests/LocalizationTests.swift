import XCTest
@testable import AgentBar

final class LocalizationTests: XCTestCase {
    func testQuitAppLabelIsLocalizedForPopoverFooter() {
        XCTAssertEqual(L.text("quit_app", .english), "Quit")
        XCTAssertEqual(L.text("quit_app", .chinese), "退出")
    }

    func testDashboardHardcodedLabelsAreLocalized() {
        XCTAssertEqual(L.text("auto_update_status", .english), "Auto-updates every minute")
        XCTAssertEqual(L.text("openai_overview", .english), "OpenAI overview")
        XCTAssertEqual(L.text("view_all_services", .english), "View all services")
        XCTAssertEqual(L.text("auto_update_status", .chinese), "数据每分钟自动更新")
        XCTAssertEqual(L.text("openai_overview", .chinese), "OpenAI 概览")
        XCTAssertEqual(L.text("view_all_services", .chinese), "查看全部服务")
    }
}
