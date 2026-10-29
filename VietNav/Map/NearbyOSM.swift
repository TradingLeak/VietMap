import Foundation
import CoreLocation
import SQLite3

/// Unverified source observations, not turn-by-turn or enforcement warnings.
struct NearbyOSM: Identifiable {
    let id: String
    let title: String
    let detail: String
    let distance: Double
}

enum NearbyOSMSearch {
    enum SearchError: LocalizedError {
        case databaseUnavailable
        var errorDescription: String? { "Không thể đọc dữ liệu OSM. Hãy thử cập nhật lại dữ liệu." }
    }
    static func search(latitude: Double, longitude: Double) throws -> [NearbyOSM] {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 85, abs(longitude) <= 180,
              let url = OfflinePlaceSearch.databaseURL() else { throw SearchError.databaseUnavailable }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            throw SearchError.databaseUnavailable
        }
        defer { sqlite3_close(db) }
        // A bounding box precedes the precise distance filter. Only explicitly tagged
        // OSM point objects are shown: do not infer cameras from surveillance tags.
        let radius = 2_000.0
        let latDelta = radius / 110_574.0
        let lonDelta = radius / (111_320.0 * max(0.1, cos(latitude * .pi / 180)))
        let sql = """
            SELECT osm_id, latitude, longitude, tags FROM features
            WHERE osm_type = 'node' AND latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?
              AND (category LIKE '%speed_camera%' OR category LIKE '%traffic_sign%')
            LIMIT 2000
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw SearchError.databaseUnavailable }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, latitude - latDelta)
        sqlite3_bind_double(stmt, 2, latitude + latDelta)
        sqlite3_bind_double(stmt, 3, longitude - lonDelta)
        sqlite3_bind_double(stmt, 4, longitude + lonDelta)
        let origin = CLLocation(latitude: latitude, longitude: longitude)
        var result: [NearbyOSM] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let lat = sqlite3_column_double(stmt, 1)
            let lon = sqlite3_column_double(stmt, 2)
            guard let raw = sqlite3_column_text(stmt, 3),
                  let data = String(cString: raw).data(using: .utf8),
                  let tags = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { continue }
            let isCamera = tags["highway"] == "speed_camera"
            let sign = tags["traffic_sign"] ?? tags["traffic_sign:forward"] ?? tags["traffic_sign:backward"]
            guard isCamera || sign != nil else { continue }
            let distance = origin.distance(from: CLLocation(latitude: lat, longitude: lon))
            guard distance <= radius else { continue }
            var details: [String] = []
            if let sign, !sign.isEmpty { details.append("Mã biển OSM: \(sign)") }
            if let speed = tags["maxspeed"], !speed.isEmpty { details.append("maxspeed: \(speed)") }
            if let direction = tags["direction"], !direction.isEmpty { details.append("Hướng OSM: \(direction)") }
            if details.isEmpty { details.append("Chưa có thông tin hướng áp dụng") }
            result.append(NearbyOSM(id: "node-\(id)", title: isCamera ? "Camera tốc độ theo OSM" : "Biển báo theo OSM", detail: details.joined(separator: " · "), distance: distance))
        }
        return result.sorted { $0.distance < $1.distance }
    }
}
