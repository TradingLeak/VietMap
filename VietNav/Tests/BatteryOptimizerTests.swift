import XCTest
import CoreLocation
@testable import VietNavCore

final class BatteryOptimizerTests: XCTestCase {
    @MainActor func testLocationPolicies() {
        let manager = CLLocationManager()
        BatteryOptimizer.adjustAccuracy(manager, context: .activeNavigation)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyBestForNavigation)
        XCTAssertEqual(manager.distanceFilter, 5)
        BatteryOptimizer.adjustAccuracy(manager, context: .idle)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyHundredMeters)
        XCTAssertEqual(manager.distanceFilter, 100)
        BatteryOptimizer.adjustAccuracy(manager, context: .backgroundIdle)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyKilometer)
        XCTAssertEqual(manager.distanceFilter, 500)
    }
}
