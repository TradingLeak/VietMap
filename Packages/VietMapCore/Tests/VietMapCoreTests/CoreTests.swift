import XCTest
@testable import VietMapCore

final class CoreTests: XCTestCase {
    private let origin = Coordinate(latitude: 20, longitude: 106)
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(_ north: Double, east: Double = 0) -> Coordinate {
        Coordinate(latitude: 20 + north / 111_195, longitude: 106 + east / 104_489)
    }

    private func dataset(roads: [RoadSegment]? = nil, hazards: [TrafficHazard] = []) -> TrafficDataset {
        TrafficDataset(id: "test", version: "1", name: "Test", updatedAt: epoch,
                       source: DatasetSource(name: "Test", url: "https://example.com", license: "CC0", attribution: "Synthetic test data"), isDemo: true,
                       roads: roads ?? [RoadSegment(id: "r1", name: "Road A", start: origin, end: point(1_000), speedLimit: 60)], hazards: hazards)
    }

    private func fix(_ second: Double = 0, north: Double = 100, speed: Double? = 50, heading: Double? = 0, accuracy: Double = 5) -> LocationFix {
        LocationFix(coordinate: point(north), speedMPS: speed.map { $0 / 3.6 }, heading: heading, horizontalAccuracy: accuracy, timestamp: epoch.addingTimeInterval(second))
    }

    private func update(_ engine: inout TrafficEngine, _ second: Double, north: Double = 100, speed: Double? = 50, heading: Double? = 0) -> EngineUpdate {
        let sample = fix(second, north: north, speed: speed, heading: heading)
        return engine.process(sample, now: sample.timestamp)
    }

    func testGeometryDistanceProjectionAndBearing() {
        XCTAssertEqual(origin.distance(to: point(1_000)), 1_000, accuracy: 1)
        XCTAssertEqual(Geo.bearing(origin, point(1_000)), 0, accuracy: 0.01)
        XCTAssertEqual(Geo.angleDifference(359, 1), 2)
        let projection = Geo.project(point(500, east: 20), onto: origin, point(1_000))
        XCTAssertEqual(projection.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(projection.distance, 20, accuracy: 0.1)
    }

    func testDatasetRoundTrip() throws {
        let original = dataset()
        XCTAssertEqual(try TrafficDataset.decode(original.encoded()), original)
    }

    func testInvalidSchemaAndMissingLicenseRejected() throws {
        var value = dataset()
        value.schemaVersion = 2
        XCTAssertThrowsError(try value.validate())
        value.schemaVersion = 1
        value.source.license = ""
        XCTAssertThrowsError(try value.validate())
    }

    func testDuplicateRoadsAndInvalidCoordinateRejected() {
        var value = dataset()
        value.roads.append(value.roads[0])
        XCTAssertThrowsError(try value.validate())
        value = dataset()
        value.roads[0].start.latitude = .nan
        XCTAssertThrowsError(try value.validate())
    }

    func testOversizedAndEmptyDatasetRejected() {
        XCTAssertThrowsError(try TrafficDataset.decode(Data(repeating: 0, count: TrafficDataset.maximumBytes + 1)))
        XCTAssertThrowsError(try dataset(roads: []).validate())
    }

    func testInvalidHazardHeadingAndDanglingRoadRejected() {
        var value = dataset(hazards: [TrafficHazard(id: "c", kind: .camera, name: "Test", coordinate: point(200), heading: 360)])
        XCTAssertThrowsError(try value.validate())
        value.hazards[0].heading = 0
        value.hazards[0].roadID = "missing"
        XCTAssertThrowsError(try value.validate())
    }

    func testRoadNeedsTwoConsecutiveFixes() throws {
        var engine = try TrafficEngine(dataset: dataset())
        XCTAssertNil(update(&engine, 0).snapshot.speedLimit)
        XCTAssertEqual(update(&engine, 1).snapshot.speedLimit, 60)
    }

    func testStaleInaccurateFutureAndInvalidSpeed() throws {
        var engine = try TrafficEngine(dataset: dataset())
        let stale = engine.process(fix(), now: epoch.addingTimeInterval(11))
        XCTAssertFalse(stale.snapshot.isReliable)
        XCTAssertFalse(engine.process(fix(30), now: epoch).snapshot.isReliable)
        XCTAssertFalse(engine.process(fix(0, accuracy: 90), now: epoch).snapshot.isReliable)
        let unknownSpeed = update(&engine, 1, speed: -1)
        XCTAssertNil(unknownSpeed.snapshot.speedKmh)
        XCTAssertNil(unknownSpeed.snapshot.speedLimit)
    }

    func testDuplicateAndOutOfOrderFixesEmitNoSpeech() throws {
        var engine = try TrafficEngine(dataset: dataset())
        _ = update(&engine, 1)
        let second = update(&engine, 2)
        XCTAssertEqual(update(&engine, 1).snapshot, second.snapshot)
        XCTAssertTrue(update(&engine, 2).announcements.isEmpty)
    }

    func testUnknownDatasetNeverInventsLimit() {
        var engine = TrafficEngine()
        _ = update(&engine, 0, speed: 100)
        let state = update(&engine, 1, speed: 100).snapshot
        XCTAssertNil(state.speedLimit)
        XCTAssertFalse(state.isOverspeed)
        XCTAssertEqual(state.speedKmh ?? 0, 100, accuracy: 0.1)
    }

    func testOneWayWrongDirectionIsUnknown() throws {
        var value = dataset()
        value.roads[0].direction = .forward
        var engine = try TrafficEngine(dataset: value)
        _ = update(&engine, 0, heading: 180)
        XCTAssertNil(update(&engine, 1, heading: 180).snapshot.speedLimit)
    }

    func testAmbiguousParallelRoadsDoNotGuessLimit() throws {
        var value = dataset()
        value.roads.append(RoadSegment(id: "r2", name: "Frontage road", start: point(0, east: 4), end: point(1_000, east: 4), speedLimit: 40))
        var engine = try TrafficEngine(dataset: value)
        _ = update(&engine, 0)
        XCTAssertNil(update(&engine, 1).snapshot.speedLimit)
    }

    func testOverspeedHysteresisAndCooldown() throws {
        var engine = try TrafficEngine(dataset: dataset())
        _ = update(&engine, 0, speed: 70)
        _ = update(&engine, 1, speed: 70)
        XCTAssertFalse(update(&engine, 2, speed: 70).snapshot.isOverspeed)
        let warning = update(&engine, 3, speed: 70)
        XCTAssertTrue(warning.snapshot.isOverspeed)
        XCTAssertEqual(warning.announcements.count, 1)
        XCTAssertTrue(update(&engine, 4, speed: 70).announcements.isEmpty)
        XCTAssertFalse(update(&engine, 5, speed: 60).snapshot.isOverspeed)
    }

    func testGPSGapDoesNotCountAsContinuousOverspeed() throws {
        var engine = try TrafficEngine(dataset: dataset())
        _ = update(&engine, 0, speed: 90)
        _ = update(&engine, 1, speed: 90)
        XCTAssertFalse(update(&engine, 20, speed: 90).snapshot.isOverspeed)
        XCTAssertNil(engine.snapshot.speedLimit)
    }

    func testDirectionalCameraAheadNotBehind() throws {
        let ahead = TrafficHazard(id: "ahead", kind: .camera, name: "Ahead", coordinate: point(240), heading: 0)
        let behind = TrafficHazard(id: "behind", kind: .camera, name: "Behind", coordinate: point(50), heading: 0)
        let opposite = TrafficHazard(id: "opposite", kind: .camera, name: "Other side", coordinate: point(230), heading: 180)
        var engine = try TrafficEngine(dataset: dataset(hazards: [ahead, behind, opposite]))
        let output = update(&engine, 0)
        XCTAssertEqual(output.snapshot.upcoming.map(\.id), ["ahead"])
        XCTAssertEqual(output.announcements.count, 1)
        XCTAssertTrue(update(&engine, 1).announcements.isEmpty)
    }

    func testCameraDoesNotSetCurrentRoadLimit() throws {
        let hazard = TrafficHazard(id: "c", kind: .camera, name: "Test", coordinate: point(240), speedLimit: 40)
        var value = dataset(hazards: [hazard])
        value.roads[0].speedLimit = nil
        var engine = try TrafficEngine(dataset: value)
        _ = update(&engine, 0)
        XCTAssertNil(update(&engine, 1).snapshot.speedLimit)
    }

    func testDisabledKindsAndStationaryGenerateNoHazardWarnings() throws {
        let camera = TrafficHazard(id: "c", kind: .camera, name: "Test", coordinate: point(240))
        var engine = try TrafficEngine(dataset: dataset(hazards: [camera]), configuration: EngineConfiguration(enabledKinds: []))
        XCTAssertTrue(update(&engine, 0).snapshot.upcoming.isEmpty)
        engine.configuration.enabledKinds = [.camera]
        XCTAssertTrue(update(&engine, 1, speed: 0).snapshot.upcoming.isEmpty)
    }

    func testLookaheadClampedEvenWithUntrustedSettings() {
        let config = EngineConfiguration(overspeedTolerance: .nan, maximumWarningDistance: .infinity)
        XCTAssertEqual(config.lookahead(speedKmh: 0), 150)
        XCTAssertEqual(config.lookahead(speedKmh: 300), 500)
        XCTAssertEqual(EngineConfiguration(maximumWarningDistance: 200).lookahead(speedKmh: 120), 200)
    }

    func testConnectedRoadLookaheadFollowsGeometry() throws {
        let a = RoadSegment(id: "a", name: "Road", start: origin, end: point(200), speedLimit: 60)
        let b = RoadSegment(id: "b", name: "Road", start: point(200), end: point(500), speedLimit: 60)
        let camera = TrafficHazard(id: "c", kind: .camera, name: "Test", coordinate: point(240), heading: 0, roadID: "b")
        var engine = try TrafficEngine(dataset: dataset(roads: [a, b], hazards: [camera]))
        XCTAssertEqual(update(&engine, 0, north: 120).snapshot.upcoming.first?.id, "c")
    }

    func testTripRejectsJumpsAndDoesNotBridgeGPSLoss() {
        var trip = Trip(startedAt: epoch)
        trip.append(fix(0), speedLimit: 60, now: epoch)
        trip.append(fix(3, north: 130), speedLimit: 60, now: epoch.addingTimeInterval(3))
        XCTAssertEqual(trip.distanceMetres, 30, accuracy: 0.1)
        trip.append(fix(6, north: 4_000), speedLimit: nil, now: epoch.addingTimeInterval(6))
        XCTAssertEqual(trip.points.count, 2)
        trip.append(fix(30, north: 600), speedLimit: nil, now: epoch.addingTimeInterval(30))
        XCTAssertEqual(trip.distanceMetres, 30, accuracy: 0.1)
        trip.finish(at: epoch.addingTimeInterval(31))
        trip.append(fix(34), speedLimit: nil, now: epoch.addingTimeInterval(34))
        XCTAssertEqual(trip.points.count, 3)
    }

    func testGPXHasSeparateSegmentsAcrossLossAndCSVHasHeader() {
        var trip = Trip(startedAt: epoch, isDemo: true)
        trip.append(fix(0), speedLimit: 60, now: epoch)
        trip.append(fix(30), speedLimit: nil, now: epoch.addingTimeInterval(30))
        let gpx = TripExport.gpx(trip)
        XCTAssertEqual(gpx.components(separatedBy: "<trkseg>").count - 1, 2)
        XCTAssertTrue(gpx.contains("VietMap demo"))
        XCTAssertTrue(TripExport.csv(trip).hasPrefix("timestamp,latitude,longitude"))
    }

    func testRouteProgressAndArrival() {
        var tracker = RouteTracker(coordinates: [origin, point(300)], instructions: [RouteInstruction(text: "Rẽ phải", distanceAlongRoute: 200)])
        let first = tracker.update(fix(0, north: 120), now: epoch)
        XCTAssertEqual(first.0?.remainingMetres ?? 0, 180, accuracy: 1)
        XCTAssertNotNil(first.1)
        XCTAssertNil(tracker.update(fix(1, north: 130), now: epoch.addingTimeInterval(1)).1)
        let arrived = tracker.update(fix(10, north: 280), now: epoch.addingTimeInterval(10))
        XCTAssertTrue(arrived.0?.hasArrived ?? false)
    }

    func testOffRouteRequiresSustainedDeviation() {
        var tracker = RouteTracker(coordinates: [origin, point(1_000)], instructions: [])
        var away = fix(0)
        away.coordinate = point(100, east: 100)
        XCTAssertFalse(tracker.update(away, now: epoch).0?.isOffRoute ?? true)
        away.timestamp = epoch.addingTimeInterval(9)
        XCTAssertTrue(tracker.update(away, now: away.timestamp).0?.isOffRoute ?? false)
    }

    func testSameCameraCanWarnOnLaterPassAfterCooldown() throws {
        let camera = TrafficHazard(id: "c", kind: .camera, name: "Test", coordinate: point(240), heading: 0)
        var engine = try TrafficEngine(dataset: dataset(hazards: [camera]))
        XCTAssertFalse(update(&engine, 0).announcements.isEmpty)
        XCTAssertTrue(update(&engine, 1).announcements.isEmpty)
        XCTAssertFalse(update(&engine, 70).announcements.isEmpty)
    }

    func testWhitespaceMetadataAndPathologicalUnicodeRejected() {
        var value = dataset()
        value.source.license = "   "
        XCTAssertThrowsError(try value.validate())
        value = dataset()
        value.roads[0].name = "a" + String(repeating: "\u{0301}", count: 2_000)
        XCTAssertThrowsError(try value.validate())
    }

    func testInvalidRouteAndNaNFixDoNotCrash() {
        var tracker = RouteTracker(coordinates: [], instructions: [])
        XCTAssertNil(tracker.update(fix(), now: epoch).0)
        var engine = TrafficEngine()
        var invalid = fix()
        invalid.coordinate.latitude = .nan
        XCTAssertFalse(engine.process(invalid, now: epoch).snapshot.isReliable)
    }
}
