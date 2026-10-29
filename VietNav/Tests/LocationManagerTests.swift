import XCTest
import CoreLocation
@testable import VietNavCore

@MainActor
final class LocationManagerTests: XCTestCase {
    private func location(speed: Double, course: Double = 120) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 21, longitude: 105), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, course: course,
                   speed: speed, timestamp: Date())
    }

    func testSpeedMovingAverageAndInvalidSpeed() {
        let subject = LocationManager(simulateOnSimulator: false)
        let source = CLLocationManager()
        subject.locationManager(source, didUpdateLocations: [location(speed: 1), location(speed: 2), location(speed: 3)])
        XCTAssertEqual(subject.speed, 7.2, accuracy: 0.001)
        XCTAssertEqual(subject.course, 120, accuracy: 0.001)
        subject.locationManager(source, didUpdateLocations: [location(speed: 4)])
        XCTAssertEqual(subject.speed, 10.8, accuracy: 0.001)
        subject.locationManager(source, didUpdateLocations: [location(speed: -1)])
        XCTAssertEqual(subject.speed, 0)
        subject.locationManager(source, didUpdateLocations: [location(speed: 1)])
        XCTAssertEqual(subject.speed, 3.6, accuracy: 0.001)
    }

    func testInvalidLocationIgnoredAndCourseRetainedWithoutHeading() {
        let subject = LocationManager(simulateOnSimulator: false)
        let source = CLLocationManager()
        subject.locationManager(source, didUpdateLocations: [location(speed: 4, course: 50)])
        subject.locationManager(source, didUpdateLocations: [location(speed: -1, course: -1)])
        XCTAssertEqual(subject.course, 50)
        let invalid = CLLocation(coordinate: .init(latitude: 21, longitude: 105), altitude: 0,
                                 horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date())
        subject.locationManager(source, didUpdateLocations: [invalid])
        XCTAssertEqual(subject.currentLocation?.horizontalAccuracy, 5)
    }
}
