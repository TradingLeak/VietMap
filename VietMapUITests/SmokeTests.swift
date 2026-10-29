import XCTest

final class SmokeTests: XCTestCase {
    @MainActor
    func testDemoHUDAndStopWithoutGPSPermission() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let demo = app.buttons["dashboard.demo"]
        // Dashboard is scrollable on smaller devices.
        for _ in 0..<4 where !demo.isHittable { app.swipeUp() }
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()
        let stop = app.buttons["dashboard.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        let hud = app.buttons["dashboard.hud"]
        for _ in 0..<3 where !hud.isHittable { app.swipeUp() }
        XCTAssertTrue(hud.isHittable)
        hud.tap()
        let close = app.buttons["hud.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        for _ in 0..<3 where !stop.isHittable { app.swipeUp() }
        stop.tap()
        let start = app.buttons["dashboard.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testSettingsDataScreenShowsNoBundledCommercialData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Cài đặt"].tap()
        let data = app.buttons["settings.data"]
        for _ in 0..<10 where !data.isHittable { app.swipeUp() }
        XCTAssertTrue(data.waitForExistence(timeout: 5))
        data.tap()
        XCTAssertTrue(app.staticTexts["Chưa có dữ liệu thực"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["data.import"].exists)
    }
}
