import XCTest
import CoreLocation
@testable import VietNavCore

@MainActor
final class SpeedWarningEngineTests: XCTestCase {
    private final class Clock { var date = Date() }
    private func sample(_ clock: Clock, lat: Double = 0, lon: Double = 0, speed: Double = 10, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 0, speed: speed, timestamp: clock.date)
    }
    private func node(_ id: Int64, lat: Double, lon: Double = 0, bearing: Double? = nil, limit: Int? = nil) -> TrafficNode {
        TrafficNode(id: id, type: .speedCamera, latitude: lat, longitude: lon, speedLimit: limit, bearing: bearing)
    }
    private func waitFor(_ engine: SpeedWarningEngine, _ date: Date) async throws {
        for _ in 0..<100 {
            if engine.lastUpdatedAt == date { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("GPS update was not processed")
    }

    func testDirectionFiltersAndWrapAround() {
        let clock = Clock(), store = FakeWarningStore(snapshot: .init(nodes: [], speedLimit: nil))
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: WarningRecorder(), now: { clock.date })
        let location = sample(clock)
        let nodes = [node(1, lat: 0.001, bearing: 359), node(2, lat: -0.001),
                     node(3, lat: 0, lon: 0.001), node(4, lat: 0.002, bearing: 45),
                     node(5, lat: 0.003, bearing: 40)]
        XCTAssertEqual(engine.filterByHeading(nodes: nodes, userLocation: location, userHeading: 0).compactMap(\.id), [1, 5])
        XCTAssertEqual(engine.angleDifference(359, 1), 2, accuracy: 0.001)
        XCTAssertEqual(engine.calculateBearing(from: location.coordinate, to: .init(latitude: 0, longitude: 1)), 90, accuracy: 0.01)
    }

    func testUnknownSignDirectionDoesNotSpeak() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        let sign = TrafficNode(id: 201, type: .noLeftTurn, latitude: 0.001, longitude: 0, bearing: nil)
        let store = FakeWarningStore(snapshot: .init(nodes: [sign], speedLimit: nil))
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
        engine.start(); defer { engine.stop() }
        engine.process(location: sample(clock), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(engine.upcomingWarnings.first?.node.type, .noLeftTurn)
        XCTAssertTrue(speaker.messages.isEmpty)
    }

    func testHeadingControlsActualWarningDelivery() async throws {
        for (heading, expected) in [(0.0, true), (180.0, false), (90.0, false)] {
            let clock = Clock(), speaker = WarningRecorder()
            let store = FakeWarningStore(snapshot: .init(nodes: [node(101, lat: 0.001, bearing: 0)], speedLimit: nil))
            let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
            engine.start()
            engine.process(location: sample(clock), heading: heading)
            try await waitFor(engine, clock.date)
            XCTAssertEqual(!speaker.messages.isEmpty, expected, "heading \(heading)")
            engine.stop()
        }
    }
    func testOverspeedToleranceBoundary() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        let engine = SpeedWarningEngine(store: FakeWarningStore(snapshot: .init(nodes: [], speedLimit: 50)), locationManager: nil, announcer: speaker, now: { clock.date })
        engine.overspeedTolerance = 5
        engine.start(); defer { engine.stop() }
        engine.process(location: sample(clock, speed: 54.9 / 3.6), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertFalse(engine.isOverSpeeding)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock, speed: 56 / 3.6), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertTrue(engine.isOverSpeeding)
    }

    func testOverspeedTimingRepeatAndInvalidSpeed() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        let store = FakeWarningStore(snapshot: .init(nodes: [], speedLimit: 50))
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
        engine.start(); defer { engine.stop() }
        engine.process(location: sample(clock, speed: 20), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertTrue(engine.isOverSpeeding)
        XCTAssertEqual(engine.currentSpeed, 72, accuracy: 0.001)
        XCTAssertEqual(speaker.messages.count, 1)
        clock.date.addTimeInterval(2)
        engine.process(location: sample(clock, speed: 20), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(engine.overspeedingDuration, 2, accuracy: 0.001)
        XCTAssertEqual(speaker.messages.count, 1)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock, speed: 20), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(speaker.messages.count, 2)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock, speed: -1), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(engine.currentSpeed, 0)
        XCTAssertFalse(engine.hasSpeedMeasurement)
        XCTAssertFalse(engine.isOverSpeeding)
        XCTAssertEqual(engine.overspeedingDuration, 0)
    }

    func testWarningDebounceFinalAndExpiry() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        let store = FakeWarningStore(snapshot: .init(nodes: [node(10, lat: 0.0018, limit: 50)], speedLimit: 50))
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
        engine.start(); defer { engine.stop() }
        engine.process(location: sample(clock), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(engine.closestWarning?.id, 10)
        XCTAssertTrue(engine.closestWarning?.hasAnnounced == true)
        XCTAssertEqual(speaker.messages.count, 1)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(speaker.messages.count, 1)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock, lat: 0.0011, speed: 20), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertTrue(speaker.messages.last?.contains("rất gần") == true)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock, lat: 0.0011, speed: 20), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(speaker.messages.filter { $0.contains("rất gần") }.count, 1)
        clock.date.addTimeInterval(301)
        engine.process(location: sample(clock), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(speaker.messages.filter { $0.contains("phía trước") }.count, 2)
    }

    func testDisabledCategoryDoesNotBlockOtherWarnings() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        speaker.disabled = [.camera]
        let toll = TrafficNode(id: 2, type: .tollBooth, latitude: 0.002, longitude: 0)
        let store = FakeWarningStore(snapshot: .init(nodes: [node(1, lat: 0.001), toll], speedLimit: nil))
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
        engine.start(); defer { engine.stop() }
        engine.process(location: sample(clock), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(speaker.messages.count, 1)
        XCTAssertTrue(speaker.messages[0].contains("trạm thu phí"))
        XCTAssertFalse(engine.upcomingWarnings[0].hasAnnounced)
        XCTAssertTrue(engine.upcomingWarnings[1].hasAnnounced)
    }

    func testUnknownHeadingDataErrorAndStaleLocationClearState() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        let store = FakeWarningStore(snapshot: .init(nodes: [node(1, lat: 0.001)], speedLimit: 50))
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
        engine.start(); defer { engine.stop() }
        engine.process(location: sample(clock, speed: 20), heading: .nan)
        try await waitFor(engine, clock.date)
        XCTAssertFalse(engine.hasReliableHeading)
        XCTAssertNil(engine.currentSpeedLimit)
        XCTAssertFalse(engine.isOverSpeeding)
        XCTAssertTrue(engine.upcomingWarnings.isEmpty)
        await store.setFailure(true)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertNotNil(engine.lastError)
        XCTAssertNil(engine.currentSpeedLimit)
        XCTAssertTrue(engine.upcomingWarnings.isEmpty)
        clock.date.addTimeInterval(11)
        engine.refreshFreshness()
        XCTAssertFalse(engine.hasFreshLocation)
        XCTAssertFalse(engine.isOverSpeeding)
    }

    func testNewerGPSReplacesInFlightQuery() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        let store = LocationDependentStore()
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
        engine.start(); defer { engine.stop() }
        engine.process(location: sample(clock, lat: 0, speed: 10), heading: 0)
        try await Task.sleep(nanoseconds: 20_000_000)
        clock.date.addTimeInterval(1)
        engine.process(location: sample(clock, lat: 0.001, speed: 10), heading: 0)
        try await waitFor(engine, clock.date)
        XCTAssertEqual(engine.currentSpeedLimit, 70)
        XCTAssertTrue(speaker.messages.isEmpty)
    }

    func testStopIgnoresLateDatabaseResult() async throws {
        let clock = Clock(), speaker = WarningRecorder()
        let store = FakeWarningStore(snapshot: .init(nodes: [node(1, lat: 0.001)], speedLimit: 50), delay: 150_000_000)
        let engine = SpeedWarningEngine(store: store, locationManager: nil, announcer: speaker, now: { clock.date })
        engine.start()
        engine.process(location: sample(clock, speed: 20), heading: 0)
        try await Task.sleep(nanoseconds: 30_000_000)
        engine.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(engine.isActive)
        XCTAssertTrue(engine.upcomingWarnings.isEmpty)
        XCTAssertTrue(speaker.messages.isEmpty)
    }
}

@MainActor
private final class WarningRecorder: SpeedWarningAnnouncing {
    var messages: [String] = []
    var disabled: Set<AlertCategory> = []
    func announce(_ message: String, category: AlertCategory, priority: AlertPriority) -> AlertDeliveryResult {
        if disabled.contains(category) { return .suppressed }
        messages.append(message); return .accepted
    }
}
private actor FakeWarningStore: TrafficWarningDataSource {
    private var snapshot: TrafficWarningSnapshot
    private var fail = false
    private let delay: UInt64
    init(snapshot: TrafficWarningSnapshot, delay: UInt64 = 0) { self.snapshot = snapshot; self.delay = delay }
    func setFailure(_ value: Bool) { fail = value }
    func load(latitude: Double, longitude: Double, heading: Double) async throws -> TrafficWarningSnapshot {
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        if fail { throw NSError(domain: "test", code: 1) }
        return snapshot
    }
}

private actor LocationDependentStore: TrafficWarningDataSource {
    func load(latitude: Double, longitude: Double, heading: Double) async throws -> TrafficWarningSnapshot {
        if latitude == 0 { try? await Task.sleep(nanoseconds: 100_000_000) }
        return TrafficWarningSnapshot(nodes: [], speedLimit: latitude == 0 ? 10 : 70)
    }
}
