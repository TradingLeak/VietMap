import XCTest
import SQLite3
@testable import VietNavCore

final class TrafficDatabaseTests: XCTestCase {
    private func memory() throws -> TrafficDatabase {
        let db = TrafficDatabase(databasePath: ":memory:", findBundledSeed: false)
        try db.setupDatabase()
        return db
    }
    private func node(_ id: Int64, lat: Double, lon: Double, type: NodeType = .speedCamera, osm: Int64? = nil) -> TrafficNode {
        TrafficNode(id: id, osmID: osm, type: type, latitude: lat, longitude: lon)
    }
    func testRTreeBoundariesFilterUpdateDelete() throws {
        let db = try memory()
        // R-Tree dùng float32, query overlap + so sánh double gốc tránh mất điểm biên.
        let boundary = node(1, lat: 21.028512345, lon: 105.854212345)
        try db.batchInsert(nodes: [boundary, node(2, lat: 21.03, lon: 105.85, type: .tollBooth)])
        XCTAssertEqual(try db.findNodesInBoundingBox(minLat: boundary.latitude, maxLat: boundary.latitude, minLon: boundary.longitude, maxLon: boundary.longitude).map(\.id), [1])
        XCTAssertEqual(try db.findNodesInBoundingBox(minLat: 21, maxLat: 22, minLon: 105, maxLon: 106, types: [.tollBooth]).map(\.id), [2])
        XCTAssertTrue(try db.findNodesInBoundingBox(minLat: 21, maxLat: 22, minLon: 105, maxLon: 106, types: []).isEmpty)
        var moved = boundary; moved.latitude = 22; moved.longitude = 106
        try db.update(node: moved)
        XCTAssertTrue(try db.findNodesInBoundingBox(minLat: 21.028, maxLat: 21.029, minLon: 105.854, maxLon: 105.855).isEmpty)
        XCTAssertEqual(try db.findNodesInBoundingBox(minLat: 22, maxLat: 22, minLon: 106, maxLon: 106).count, 1)
        try db.delete(id: 1)
        XCTAssertTrue(try db.findNodesInBoundingBox(minLat: 22, maxLat: 22, minLon: 106, maxLon: 106).isEmpty)
    }
    func testBatchRollbackOnDuplicateOSMID() throws {
        let db = try memory()
        XCTAssertThrowsError(try db.batchInsert(nodes: [node(1, lat: 21, lon: 105, osm: 42), node(2, lat: 21, lon: 105, osm: 42)]))
        XCTAssertTrue(try db.findNodesInBoundingBox(minLat: 20, maxLat: 22, minLon: 104, maxLon: 106).isEmpty)
    }
    func testNearestRadiusSortAndAntimeridian() throws {
        let db = try memory()
        try db.batchInsert(nodes: [node(1, lat: 0, lon: 179.999), node(2, lat: 0, lon: -179.999), node(3, lat: 0, lon: 179.98)])
        XCTAssertEqual(try db.findNearestNodes(latitude: 0, longitude: 179.999, radiusMeters: 300).map(\.id), [1, 2])
        XCTAssertEqual(try db.findNearestNodes(latitude: 0, longitude: 179.999, radiusMeters: 300, limit: 1).map(\.id), [1])
        XCTAssertThrowsError(try db.findNearestNodes(latitude: .nan, longitude: 0))
    }
    func testSpeedLimitSpatialAndBearing() throws {
        let db = try memory()
        try db.insertRoadSegment(RoadSegment(id: 1, maxSpeed: 50, coordinates: [.init(latitude: 21.0, longitude: 105.0), .init(latitude: 21.01, longitude: 105.0)]))
        try db.insertRoadSegment(RoadSegment(id: 2, maxSpeed: 70, coordinates: [.init(latitude: 21.005, longitude: 105.002), .init(latitude: 21.015, longitude: 105.002)]))
        XCTAssertEqual(try db.findSpeedLimitAt(latitude: 21.005, longitude: 105, bearing: 0), 50)
        XCTAssertEqual(try db.findSpeedLimitAt(latitude: 21.005, longitude: 105, bearing: 180), 50)
        XCTAssertNil(try db.findSpeedLimitAt(latitude: 21.005, longitude: 105, bearing: 90))
        XCTAssertNil(try db.findSpeedLimitAt(latitude: 20, longitude: 105, bearing: 0))
        XCTAssertThrowsError(try db.insertRoadSegment(RoadSegment(coordinates: [.init(latitude: 21, longitude: 105)])))
    }
    func testPendingReports() throws {
        let db = try memory()
        try db.saveUserReport(UserReport(type: .railwayCrossing, latitude: 21, longitude: 105, description: "test", reportedAt: 1))
        try db.saveUserReport(UserReport(type: .tollBooth, uploaded: true))
        XCTAssertEqual(try db.getPendingReports().map(\.description), ["test"])
    }
    func testSeedCopiedOnlyOnceAndMigrationIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let seedPath = dir.appendingPathComponent("seed.sqlite").path
        do {
            let seed = TrafficDatabase(databasePath: seedPath, findBundledSeed: false)
            try seed.insert(node: node(1, lat: 21, lon: 105))
        }
        let path = dir.appendingPathComponent("db.sqlite").path
        let db = TrafficDatabase(databasePath: path, seedURL: URL(fileURLWithPath: seedPath), findBundledSeed: false)
        try db.setupDatabase(); try db.setupDatabase()
        XCTAssertEqual(try db.findNodesInBoundingBox(minLat: 20, maxLat: 22, minLon: 104, maxLon: 106).count, 1)
        try db.delete(id: 1)
        let reopened = TrafficDatabase(databasePath: path, seedURL: URL(fileURLWithPath: seedPath), findBundledSeed: false)
        XCTAssertTrue(try reopened.findNodesInBoundingBox(minLat: 20, maxLat: 22, minLon: 104, maxLon: 106).isEmpty)
    }
    func testV1DatabaseMigratesToV2WithoutLosingReports() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("legacy.sqlite").path
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &connection), SQLITE_OK)
        let schema = try TrafficDatabase.initialSchema() + """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES ('v1_traffic');
            INSERT INTO user_reports(type, description, uploaded) VALUES ('INCIDENT','kept',0);
            """
        let result = sqlite3_exec(connection, schema, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK)
        sqlite3_close(connection)
        guard result == SQLITE_OK else { return }
        let database = TrafficDatabase(databasePath: path, findBundledSeed: false)
        try database.setupDatabase()
        XCTAssertEqual(try database.getPendingReports().first?.description, "kept")
        XCTAssertEqual(try database.trafficDataVersion(), "")
    }

    func testTrafficUpdateMigrationAndReportsSurvive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let seed = TrafficDatabase(databasePath: dir.appendingPathComponent("seed.sqlite").path, findBundledSeed: false)
        try seed.insert(node: node(100, lat: 21, lon: 105, osm: 100))
        let db = TrafficDatabase(databasePath: dir.appendingPathComponent("current.sqlite").path, findBundledSeed: false)
        try db.insert(node: node(1, lat: 20, lon: 105, osm: 1))
        try db.saveUserReport(UserReport(type: .incident, latitude: 21, longitude: 105, description: "local"))
        XCTAssertTrue(try db.installTrafficUpdate(from: dir.appendingPathComponent("seed.sqlite").path, version: "20261029T000000Z"))
        XCTAssertEqual(try db.findNodesInBoundingBox(minLat: 19, maxLat: 22, minLon: 104, maxLon: 106).map(\.osmID), [100])
        XCTAssertEqual(try db.getPendingReports().first?.description, "local")
        XCTAssertFalse(try db.installTrafficUpdate(from: dir.appendingPathComponent("seed.sqlite").path, version: "20261028T000000Z"))
        XCTAssertThrowsError(try db.installTrafficUpdate(from: dir.appendingPathComponent("seed.sqlite").path, version: "invalid"))
    }

    func testUpdateConflictRollsBackAllOSMChanges() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let seed = TrafficDatabase(databasePath: dir.appendingPathComponent("incoming.sqlite").path, findBundledSeed: false)
        try seed.insert(node: node(100, lat: 21, lon: 105, osm: 100))
        let db = TrafficDatabase(databasePath: dir.appendingPathComponent("local.sqlite").path, findBundledSeed: false)
        try db.insert(node: node(1, lat: 20, lon: 105, osm: 1))
        try db.insert(node: TrafficNode(id: 2, osmID: 100, type: .speedCamera, latitude: 20, longitude: 105, source: "LOCAL"))
        XCTAssertThrowsError(try db.installTrafficUpdate(from: dir.appendingPathComponent("incoming.sqlite").path, version: "20261029T000000Z"))
        let nodes = try db.findNodesInBoundingBox(minLat: 19, maxLat: 22, minLon: 104, maxLon: 106)
        XCTAssertEqual(Set(nodes.compactMap(\.osmID)), Set([1, 100]))
        XCTAssertEqual(try db.trafficDataVersion(), "")
    }

    /// Benchmarks chỉ chạy khi được yêu cầu; SLA chỉ enforce khi đặt VIETNAV_ENFORCE_PERF=1.
    func testHundredThousandInsertAndSpatialLatency() throws {
        guard ProcessInfo.processInfo.environment["VIETNAV_BENCHMARK"] == "1" else { throw XCTSkip("Đặt VIETNAV_BENCHMARK=1 để đo trên thiết bị") }
        let db = try memory()
        let nodes = (0..<100_000).map { i in
            node(Int64(i + 1), lat: 20 + Double(i / 1000) * 0.001, lon: 105 + Double(i % 1000) * 0.001)
        }
        let begin = CFAbsoluteTimeGetCurrent()
        try db.batchInsert(nodes: nodes)
        let insertElapsed = CFAbsoluteTimeGetCurrent() - begin
        let all = try db.findNodesInBoundingBox(minLat: 19, maxLat: 21, minLon: 104, maxLon: 107)
        let totalElapsed = CFAbsoluteTimeGetCurrent() - begin
        XCTAssertEqual(all.count, 100_000)
        let q = CFAbsoluteTimeGetCurrent()
        let small = try db.findNodesInBoundingBox(minLat: 20.02, maxLat: 20.021, minLon: 105.02, maxLon: 105.021)
        let queryElapsed = CFAbsoluteTimeGetCurrent() - q
        XCTAssertFalse(small.isEmpty)
        print("100k insert: \(insertElapsed)s; insert and full query: \(totalElapsed)s; spatial: \(queryElapsed)s")
        if ProcessInfo.processInfo.environment["VIETNAV_ENFORCE_PERF"] == "1" {
            XCTAssertLessThan(totalElapsed, 1, "100k insert + full query target")
            XCTAssertLessThan(queryElapsed, 0.010, "R-Tree query target")
        }
    }

    func testSpatialPerformanceOptional() throws {
        guard ProcessInfo.processInfo.environment["VIETNAV_BENCHMARK"] == "1" else { throw XCTSkip("Đặt VIETNAV_BENCHMARK=1") }
        let db = try memory()
        try db.batchInsert(nodes: (0..<100_000).map { i in
            node(Int64(i + 1), lat: 20 + Double(i / 1000) * 0.001, lon: 105 + Double(i % 1000) * 0.001)
        })
        measure {
            do { _ = try db.findNodesInBoundingBox(minLat: 20.02, maxLat: 20.021, minLon: 105.02, maxLon: 105.021) }
            catch { XCTFail("Spatial query failed: \(error)") }
        }
    }
}
