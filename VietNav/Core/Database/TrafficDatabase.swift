import Foundation
import GRDB

public enum TrafficDatabaseError: Error {
    case invalidCoordinates, invalidBoundingBox, invalidRadius, invalidLimit, invalidBearing, invalidGeometry, missingID
    case invalidUpdate, staleUpdate
}

/// DatabaseQueue serialize mọi thao tác; R-Tree được đồng bộ bởi trigger trong transaction SQLite.
public final class TrafficDatabase {
    public static let shared = TrafficDatabase()
    private let lock = NSLock()
    private var dbQueue: DatabaseQueue?
    private let databasePath: String?
    private let seedURL: URL?
    private let findBundledSeed: Bool

    /// Không truyền path để dùng Documents. Dùng ":memory:" cho test; seed phải là DB đã migration.
    public init(databasePath: String? = nil, seedURL: URL? = nil, findBundledSeed: Bool = true) {
        self.databasePath = databasePath; self.seedURL = seedURL; self.findBundledSeed = findBundledSeed
    }

    public func setupDatabase() throws {
        lock.lock(); defer { lock.unlock() }
        guard dbQueue == nil else { return }
        let path: String
        if let databasePath { path = databasePath }
        else {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            path = documents.appendingPathComponent("vietnam_traffic.sqlite").path
        }
        if path != ":memory:" {
            let destination = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let seed = seedURL ?? (findBundledSeed ? Bundle.main.url(forResource: "vietnam_traffic", withExtension: "sqlite") : nil)
            if !FileManager.default.fileExists(atPath: path), let seed {
                // Copy tạm cùng thư mục và rename để tránh để lại file đích chưa hoàn chỉnh.
                let temp = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).sqlite")
                defer { try? FileManager.default.removeItem(at: temp) }
                try FileManager.default.copyItem(at: seed, to: temp)
                try FileManager.default.moveItem(at: temp, to: destination)
            }
        }
        let queue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(queue)
        dbQueue = queue
    }

    /// Copy seed (nếu có) và migrate ngoài main thread. Không ghi đè DB đã tồn tại.
    public func importInitialDataIfNeeded() async throws {
        try await Task.detached(priority: .utility) { try self.setupDatabase() }.value
    }

    private func queue() throws -> DatabaseQueue {
        try setupDatabase()
        lock.lock(); defer { lock.unlock() }
        return dbQueue!
    }

    static func initialSchema() throws -> String {
        guard let url = Bundle.module.url(forResource: "schema_v1", withExtension: "sql") else { throw CocoaError(.fileNoSuchFile) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func trafficDataVersion() throws -> String {
        try queue().read { db in try String.fetchOne(db, sql: "SELECT version FROM traffic_data_version WHERE id=1") ?? "" }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_traffic") { db in
            try db.execute(sql: try initialSchema())
        }
        migrator.registerMigration("v2_traffic_data_version") { db in
            try db.execute(sql: "CREATE TABLE traffic_data_version (id INTEGER PRIMARY KEY CHECK(id=1), version TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO traffic_data_version(id, version) VALUES (1, '')")
        }
        return migrator
    }

    /// Dữ liệu OSM thay thế trong một transaction; báo cáo người dùng và node không phải OSM được giữ.
    /// Nguồn phải là file seed v1 đã được kiểm tra SHA-256 trước khi gọi.
    func installTrafficUpdate(from path: String, version: String) throws -> Bool {
        guard version.range(of: "^[0-9]{8}T[0-9]{6}Z$", options: .regularExpression) != nil else { throw TrafficDatabaseError.invalidUpdate }
        return try queue().writeWithoutTransaction { db in
            try db.execute(sql: "ATTACH DATABASE ? AS incoming", arguments: [path])
            defer { try? db.execute(sql: "DETACH DATABASE incoming") }
            guard try String.fetchOne(db, sql: "PRAGMA incoming.integrity_check") == "ok",
                  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM incoming.grdb_migrations WHERE identifier='v1_traffic'") == 1,
                  (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM incoming.traffic_nodes") ?? 0) > 0,
                  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM incoming.traffic_nodes WHERE latitude NOT BETWEEN -90 AND 90 OR longitude NOT BETWEEN -180 AND 180 OR source != 'OSM' OR type NOT IN ('SPEED_CAMERA','RED_LIGHT_CAMERA','SPEED_LIMIT','RESIDENTIAL_IN','RESIDENTIAL_OUT','TOLL_BOOTH','RAILWAY_CROSSING','NO_OVERTAKING','INCIDENT')") == 0
            else { throw TrafficDatabaseError.invalidUpdate }
            var installed = false
            try db.inTransaction {
                let current = try String.fetchOne(db, sql: "SELECT version FROM traffic_data_version WHERE id=1") ?? ""
                guard version > current else { return .commit }
                try db.execute(sql: "DELETE FROM traffic_nodes WHERE source='OSM'")
                try db.execute(sql: "DELETE FROM road_segments")
                try db.execute(sql: """
                    INSERT INTO traffic_nodes (osm_id,type,latitude,longitude,speed_limit,bearing,road_name,road_ref,province,district,verified,source,created_at,updated_at)
                    SELECT osm_id,type,latitude,longitude,speed_limit,bearing,road_name,road_ref,province,district,verified,source,created_at,updated_at FROM incoming.traffic_nodes
                    """)
                try db.execute(sql: """
                    INSERT INTO road_segments (osm_way_id,road_name,road_type,max_speed,geometry,province,min_lat,max_lat,min_lon,max_lon)
                    SELECT osm_way_id,road_name,road_type,max_speed,geometry,province,min_lat,max_lat,min_lon,max_lon FROM incoming.road_segments
                    """)
                try db.execute(sql: "UPDATE traffic_data_version SET version=? WHERE id=1", arguments: [version])
                installed = true
                return .commit
            }
            return installed
        }
    }

    public func findNodesInBoundingBox(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
                                       types: [NodeType]? = nil) throws -> [TrafficNode] {
        guard minLat.isFinite, maxLat.isFinite, minLon.isFinite, maxLon.isFinite,
              minLat >= -90, maxLat <= 90, minLat <= maxLat,
              minLon >= -180, maxLon <= 180, minLon <= maxLon else { throw TrafficDatabaseError.invalidBoundingBox }
        if let types, types.isEmpty { return [] }
        var sql = """
        SELECT t.* FROM traffic_nodes_rtree r JOIN traffic_nodes t ON t.id = r.id
        WHERE r.min_lat <= ? AND r.max_lat >= ? AND r.min_lon <= ? AND r.max_lon >= ?
          AND t.latitude >= ? AND t.latitude <= ? AND t.longitude >= ? AND t.longitude <= ?
        """
        var args: StatementArguments = [maxLat, minLat, maxLon, minLon, minLat, maxLat, minLon, maxLon]
        if let types {
            sql += " AND t.type IN (" + Array(repeating: "?", count: types.count).joined(separator: ",") + ")"
            for type in types { args += [type.rawValue] }
        }
        sql += " ORDER BY t.id"
        return try queue().read { db in try TrafficNode.fetchAll(db, sql: sql, arguments: args) }
    }

    public func findNearestNodes(latitude: Double, longitude: Double, radiusMeters: Double = 2000, limit: Int = 50) throws -> [TrafficNode] {
        try Self.validate(latitude, longitude)
        guard radiusMeters.isFinite, radiusMeters >= 0 else { throw TrafficDatabaseError.invalidRadius }
        guard limit >= 0 else { throw TrafficDatabaseError.invalidLimit }
        guard limit > 0 else { return [] }
        var candidates: [Int64: TrafficNode] = [:]
        for box in Self.searchBoxes(lat: latitude, lon: longitude, radius: radiusMeters) {
            for node in try findNodesInBoundingBox(minLat: box.south, maxLat: box.north, minLon: box.west, maxLon: box.east) {
                if let id = node.id { candidates[id] = node }
            }
        }
        return candidates.values.compactMap { node -> (TrafficNode, Double)? in
            let distance = Self.distance(latitude, longitude, node.latitude, node.longitude)
            return distance <= radiusMeters ? (node, distance) : nil
        }.sorted { a, b in a.1 == b.1 ? (a.0.id ?? 0) < (b.0.id ?? 0) : a.1 < b.1 }
         .prefix(limit).map(\.0)
    }

    public func insert(node: TrafficNode) throws {
        try Self.validate(node.latitude, node.longitude)
        try queue().write { db in try node.insert(db) }
    }
    public func batchInsert(nodes: [TrafficNode]) throws {
        try queue().write { db in
            for node in nodes { try Self.validate(node.latitude, node.longitude); try node.insert(db) }
        }
    }
    public func update(node: TrafficNode) throws {
        guard node.id != nil else { throw TrafficDatabaseError.missingID }
        try Self.validate(node.latitude, node.longitude)
        try queue().write { db in try node.update(db) }
    }
    public func delete(id: Int64) throws {
        try queue().write { db in _ = try TrafficNode.deleteOne(db, key: id) }
    }
    public func saveUserReport(_ report: UserReport) throws {
        if let lat = report.latitude, let lon = report.longitude { try Self.validate(lat, lon) }
        else if report.latitude != nil || report.longitude != nil { throw TrafficDatabaseError.invalidCoordinates }
        try queue().write { db in try report.insert(db) }
    }
    public func getPendingReports() throws -> [UserReport] {
        try queue().read { db in try UserReport.fetchAll(db, sql: "SELECT * FROM user_reports WHERE uploaded = 0 ORDER BY reported_at, id") }
    }

    /// Ghi một đoạn LineString và bbox trong cùng transaction với R-Tree.
    public func insertRoadSegment(_ segment: RoadSegment) throws {
        guard segment.coordinates.count >= 2 else { throw TrafficDatabaseError.invalidGeometry }
        for c in segment.coordinates { try Self.validate(c.latitude, c.longitude) }
        let lats = segment.coordinates.map(\.latitude), lons = segment.coordinates.map(\.longitude)
        let geometry = LineString(type: "LineString", coordinates: segment.coordinates.map { [$0.longitude, $0.latitude] })
        let json = String(decoding: try JSONEncoder().encode(geometry), as: UTF8.self)
        try queue().write { db in
            try db.execute(sql: """
                INSERT INTO road_segments (id,osm_way_id,road_name,road_type,max_speed,geometry,province,min_lat,max_lat,min_lon,max_lon)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """, arguments: [segment.id, segment.osmWayID, segment.roadName, segment.roadType, segment.maxSpeed,
                                   json, segment.province, lats.min(), lats.max(), lons.min(), lons.max()])
        }
    }

    /// Ước lượng: đoạn có max_speed gần nhất trong 30 m và lệch hướng <= 60° (cho phép cả hai chiều).
    /// Không thay thế map-matching, không phân biệt đường một chiều/tầng cầu hoặc biển theo chiều.
    public func findSpeedLimitAt(latitude: Double, longitude: Double, bearing: Double) throws -> Int? {
        try Self.validate(latitude, longitude)
        guard bearing.isFinite, bearing >= 0, bearing <= 360 else { throw TrafficDatabaseError.invalidBearing }
        let boxes = Self.searchBoxes(lat: latitude, lon: longitude, radius: 30)
        return try queue().read { db in
            var seen = Set<Int64>()
            var best: (distance: Double, speed: Int, id: Int64)?
            for box in boxes {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT s.id,s.max_speed,s.geometry FROM road_segments_rtree r
                    JOIN road_segments s ON s.id=r.id
                    WHERE r.min_lat <= ? AND r.max_lat >= ? AND r.min_lon <= ? AND r.max_lon >= ?
                      AND s.max_speed IS NOT NULL
                    """, arguments: [box.north, box.south, box.east, box.west])
                for row in rows {
                    let id: Int64 = row["id"]
                    guard seen.insert(id).inserted else { continue }
                    let json: String = row["geometry"]
                    let speed: Int = row["max_speed"]
                    guard speed > 0, let line = try? JSONDecoder().decode(LineString.self, from: Data(json.utf8)),
                          line.type == "LineString", line.coordinates.count >= 2 else { continue }
                    for pair in zip(line.coordinates, line.coordinates.dropFirst()) {
                        guard pair.0.count >= 2, pair.1.count >= 2,
                              (try? Self.validate(pair.0[1], pair.0[0])) != nil,
                              (try? Self.validate(pair.1[1], pair.1[0])) != nil,
                              let match = Self.segmentDistance(latitude, longitude, pair.0, pair.1, bearing) else { continue }
                        if match <= 30 && (best == nil || match < best!.distance || (match == best!.distance && id < best!.id)) {
                            best = (match, speed, id)
                        }
                    }
                }
            }
            return best?.speed
        }
    }

    private struct LineString: Codable { let type: String; let coordinates: [[Double]] }
    private struct Box { let south: Double, north: Double, west: Double, east: Double }
    private static let earthRadius = 6_371_000.0
    private static func validate(_ lat: Double, _ lon: Double) throws {
        guard lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else {
            throw TrafficDatabaseError.invalidCoordinates
        }
    }
    private static func searchBoxes(lat: Double, lon: Double, radius: Double) -> [Box] {
        let angular = min(.pi, radius / earthRadius)
        let deltaLat = angular * 180 / .pi
        let south = max(-90, lat - deltaLat), north = min(90, lat + deltaLat)
        if south <= -90 || north >= 90 || angular >= .pi / 2 {
            return [Box(south: south, north: north, west: -180, east: 180)]
        }
        let ratio = min(1, sin(angular) / cos(lat * .pi / 180))
        let deltaLon = asin(ratio) * 180 / .pi
        let west = lon - deltaLon, east = lon + deltaLon
        if west <= -180 {
            return [Box(south: south, north: north, west: -180, east: east), Box(south: south, north: north, west: west + 360, east: 180)]
        }
        if east >= 180 {
            return [Box(south: south, north: north, west: west, east: 180), Box(south: south, north: north, west: -180, east: east - 360)]
        }
        return [Box(south: south, north: north, west: west, east: east)]
    }
    private static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let a = lat1 * .pi / 180, b = lat2 * .pi / 180
        let dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(a) * cos(b) * pow(sin(dLon / 2), 2)
        return 2 * earthRadius * asin(sqrt(min(1, max(0, h))))
    }
    private static func wrappedLongitude(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }; if value < -180 { value += 360 }
        return value
    }
    private static func segmentDistance(_ lat: Double, _ lon: Double, _ a: [Double], _ b: [Double], _ bearing: Double) -> Double? {
        let scale = earthRadius * .pi / 180
        let cosLat = cos(lat * .pi / 180)
        let x1 = wrappedLongitude(a[0] - lon) * scale * cosLat, y1 = (a[1] - lat) * scale
        let dx = wrappedLongitude(b[0] - a[0]) * scale * cosLat, dy = (b[1] - a[1]) * scale
        let length2 = dx * dx + dy * dy
        guard length2 > 0 else { return nil }
        let direction = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let delta = abs(wrappedLongitude(direction - bearing))
        guard min(delta, 180 - delta) <= 60 else { return nil }
        let t = min(1, max(0, -(x1 * dx + y1 * dy) / length2))
        return hypot(x1 + t * dx, y1 + t * dy)
    }
}
