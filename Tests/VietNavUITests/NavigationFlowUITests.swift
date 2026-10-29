import XCTest

final class NavigationFlowUITests: XCTestCase {
    func testLaunchSearchAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-vietnav-ui-testing"]
        addUIInterruptionMonitor(withDescription: "Location and notification permissions") { alert in
            for title in ["Allow While Using App", "Allow Once", "Allow", "Cho phép khi dùng ứng dụng", "Cho phép"] {
                let button = alert.buttons[title]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["Tìm địa điểm"].waitForExistence(timeout: 20))
        app.buttons["Về vị trí của tôi"].tap()
        // Kích hoạt interruption monitor nếu hệ thống hiển thị hộp thoại quyền.
        app.tap()
        app.buttons["Tìm địa điểm"].tap()
        let field = app.textFields["Nhập địa điểm cần tìm"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("dia diem test")
        app.buttons["Tìm"].tap()
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Điểm thử nghiệm")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        let calculate = app.buttons["Tính tuyến đường"]
        XCTAssertTrue(calculate.waitForExistence(timeout: 10))
        calculate.tap()
        let start = app.buttons["Bắt đầu dẫn đường"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "Cần quyền vị trí simulator và một GPS fix mới")
        start.tap()
        XCTAssertTrue(app.buttons["Dừng dẫn đường"].waitForExistence(timeout: 10))
    }
}
