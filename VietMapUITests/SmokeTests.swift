import XCTest

final class SmokeTests: XCTestCase {
    @MainActor
    func testDemoHUDAndStopWithoutGPSPermission() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let demo = app.buttons["dashboard.demo"]
        XCTAssertTrue(reveal(demo, in: app))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: demo)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        demo.tap()
        let stop = app.buttons["dashboard.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        let hud = app.buttons["dashboard.hud"]
        XCTAssertTrue(reveal(hud, in: app))
        hud.tap()
        let close = app.buttons["hud.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(reveal(stop, in: app))
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
        XCTAssertTrue(reveal(data, in: app, attempts: 10))
        data.tap()
        XCTAssertTrue(app.staticTexts["Chưa có dữ liệu thực"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["data.import"].exists)
    }

    /// Drag the scroll view's outer gutter, never the embedded map or a slider.
    /// A mode transition can move a button above OR below the viewport.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            let above = element.exists && element.frame.maxY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: above ? 0.25 : 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: above ? 0.78 : 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return element.exists && element.isHittable
    }
}
