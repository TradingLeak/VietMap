import XCTest
import CoreLocation
import OSMData
@testable import VietNavCore

@MainActor
final class NavigationEngineTests: XCTestCase {
    private let base = Date()
    private func point(_ lat: Double, _ lon: Double = 0, seconds: TimeInterval, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat, longitude: lon), altitude: 0, horizontalAccuracy: accuracy,
                   verticalAccuracy: 5, course: 0, speed: 10, timestamp: base.addingTimeInterval(seconds))
    }
    private func route() -> Route {
        let start = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let turn = CLLocationCoordinate2D(latitude: 0.009, longitude: 0)
        let end = CLLocationCoordinate2D(latitude: 0.018, longitude: 0)
        return Route(geometry: [start, turn, end], distance: 2000, duration: 200,
                     steps: [
                        RouteStep(instruction: "Bắt đầu đi", distance: 1000, duration: 100, maneuver: .depart, streetName: "", coordinate: start),
                        RouteStep(instruction: "Rẽ phải vào A", distance: 1000, duration: 100, maneuver: .turnRight, streetName: "A", coordinate: turn),
                        RouteStep(instruction: "Đã đến nơi", distance: 0, duration: 0, maneuver: .arrive, streetName: "", coordinate: end)
                     ], bbox: BoundingBox(south: 0, west: 0, north: 0.018, east: 0))
    }
    func testSnapProgressInstructionsAndArrival() throws {
        let announcer = RecordingAnnouncer()
        let engine = NavigationEngine(service: StubRouting(route: route()), locationManager: nil, announcer: announcer)
        engine.startNavigation(route: route())
        let snap = try XCTUnwrap(engine.snapToRoute(location: point(0.0045, 0.0001, seconds: -8)))
        XCTAssertEqual(snap.snappedLocation.coordinate.latitude, 0.0045, accuracy: 0.00001)
        XCTAssertEqual(snap.distanceFromRoute, 11.1, accuracy: 0.5)
        engine.updateProgress(with: point(0.00001, seconds: -9))
        XCTAssertEqual(engine.currentStepIndex, 1)
        XCTAssertTrue(announcer.messages.last?.hasPrefix("Sau 1 ki-lô-mét") == true)
        engine.updateProgress(with: point(0.0045, seconds: -8))
        XCTAssertEqual(engine.progressFraction, 0.25, accuracy: 0.01)
        XCTAssertEqual(engine.distanceRemaining, 1500, accuracy: 5)
        XCTAssertTrue(announcer.messages.last?.hasPrefix("Sau 500 mét") == true)
        engine.updateProgress(with: point(0.0045, seconds: -7))
        XCTAssertEqual(announcer.messages.count, 2)
        engine.updateProgress(with: point(0.0075, seconds: -6))
        XCTAssertTrue(announcer.messages.last?.hasPrefix("Chuẩn bị") == true)
        engine.updateProgress(with: point(0.0087, seconds: -5))
        XCTAssertTrue(announcer.messages.last?.hasPrefix("Ngay bây giờ") == true)
        engine.updateProgress(with: point(0.009, seconds: -4))
        XCTAssertEqual(engine.currentStepIndex, 2)
        let progress = engine.progressFraction
        engine.updateProgress(with: point(0.008, seconds: -3))
        XCTAssertEqual(engine.progressFraction, progress, accuracy: 0.00001)
        engine.updateProgress(with: point(0.018, seconds: -2))
        XCTAssertTrue(engine.isArrived)
        XCTAssertFalse(engine.isNavigating)
        XCTAssertEqual(engine.distanceRemaining, 0)
        XCTAssertEqual(announcer.messages.last, "Đã đến nơi")
    }
    func testAccuracyAndOffRouteNeedsThreeSpacedUpdates() async throws {
        let newRoute = route()
        let service = StubRouting(route: newRoute)
        let engine = NavigationEngine(service: service, locationManager: nil, announcer: RecordingAnnouncer())
        engine.startNavigation(route: route())
        engine.updateProgress(with: point(0.003, 0.001, seconds: -7, accuracy: 100))
        XCTAssertFalse(engine.isOffRoute)
        engine.updateProgress(with: point(0.003, 0.001, seconds: -6))
        engine.updateProgress(with: point(0.003, 0.001, seconds: -5))
        XCTAssertTrue(engine.isOffRoute)
        let initialCalls = await service.calls()
        XCTAssertEqual(initialCalls, 0)
        engine.updateProgress(with: point(0.003, 0.001, seconds: -4))
        for _ in 0..<20 {
            if engine.currentRoute?.id == newRoute.id && !engine.isRerouting { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let finalCalls = await service.calls()
        XCTAssertEqual(finalCalls, 1)
        XCTAssertEqual(engine.currentRoute?.id, newRoute.id)
        XCTAssertFalse(engine.isRerouting)
    }
    func testReturningToRouteCancelsStaleReroute() async throws {
        let oldRoute = route(), replacement = route()
        let service = StubRouting(route: replacement, delayNanoseconds: 150_000_000)
        let engine = NavigationEngine(service: service, locationManager: nil, announcer: RecordingAnnouncer())
        engine.startNavigation(route: oldRoute)
        engine.updateProgress(with: point(0.003, 0.001, seconds: -6))
        engine.updateProgress(with: point(0.003, 0.001, seconds: -5))
        engine.updateProgress(with: point(0.003, 0.001, seconds: -4))
        for _ in 0..<20 {
            if engine.isRerouting { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(engine.isRerouting)
        engine.updateProgress(with: point(0.003, 0, seconds: -3))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(engine.isOffRoute)
        XCTAssertFalse(engine.isRerouting)
        XCTAssertEqual(engine.currentRoute?.id, oldRoute.id)
    }

    func testReroutePreservesFutureWaypointsAndProfile() async {
        let original = route()
        let futureStop = CLLocationCoordinate2D(latitude: 0.014, longitude: 0)
        let custom = Route(geometry: original.geometry, distance: original.distance, duration: original.duration,
                           steps: original.steps, bbox: original.bbox, profile: .bicycle,
                           waypoints: [.init(latitude: 0.004, longitude: 0), futureStop],
                           destination: original.geometry.last)
        let service = StubRouting(route: route())
        let engine = NavigationEngine(service: service, locationManager: nil, announcer: RecordingAnnouncer())
        engine.startNavigation(route: custom)
        engine.updateProgress(with: point(0.006, seconds: -2))
        await engine.recalculateRoute()
        let request = await service.lastRequest()
        XCTAssertEqual(request?.profile, .bicycle)
        XCTAssertEqual(request?.waypoints.count, 1)
        XCTAssertEqual(request?.waypoints.first?.latitude ?? 0, futureStop.latitude, accuracy: 0.000001)
    }

    func testInvalidRouteAndStopResetState() {
        let engine = NavigationEngine(service: StubRouting(route: route()), locationManager: nil, announcer: RecordingAnnouncer())
        let bad = Route(geometry: [], distance: 0, duration: 0, steps: [], bbox: BoundingBox(south: 0, west: 0, north: 1, east: 1))
        engine.startNavigation(route: bad)
        XCTAssertFalse(engine.isNavigating)
        XCTAssertNotNil(engine.lastError)
        engine.startNavigation(route: route())
        engine.stopNavigation()
        XCTAssertNil(engine.currentRoute)
        XCTAssertEqual(engine.progressFraction, 0)
        XCTAssertNil(engine.estimatedArrivalTime)
    }
    func testOSMTurnLanesDoNotInventRecommendations() {
        let lanes = LaneGuidance.parseOSMTurnLanes("left|through;right||reverse")
        XCTAssertEqual(lanes.count, 4)
        XCTAssertEqual(lanes[1].indications, ["through", "right"])
        XCTAssertEqual(lanes[2].indications, [])
        XCTAssertTrue(lanes.allSatisfy { $0.valid == nil })
    }
}

@MainActor
private final class RecordingAnnouncer: NavigationAnnouncing {
    var messages: [String] = []
    func announce(_ text: String) { messages.append(text) }
    func stop() {}
}

private actor StubRouting: RoutingServiceProtocol {
    private let result: Route
    private var count = 0
    private let delayNanoseconds: UInt64
    private var captured: (waypoints: [CLLocationCoordinate2D], profile: RouteProfile)?
    init(route: Route, delayNanoseconds: UInt64 = 0) { result = route; self.delayNanoseconds = delayNanoseconds }
    func calls() -> Int { count }
    func lastRequest() -> (waypoints: [CLLocationCoordinate2D], profile: RouteProfile)? { captured }
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, waypoints: [CLLocationCoordinate2D], profile: RouteProfile) async throws -> Route { count += 1; captured = (waypoints, profile); if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }; return result }
    func calculateRoutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, waypoints: [CLLocationCoordinate2D], profile: RouteProfile, alternatives: Bool) async throws -> [Route] { [result] }
}
