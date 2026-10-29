import Foundation
import SQLite3
import CoreLocation

struct OfflinePlace: Identifiable {
    let id: String
    let name: String
    let kind: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

enum OfflinePlaceSearch {
    static func databaseURL() -> URL? {
        let fm = FileManager.default
        if let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let updated = base.appendingPathComponent("vietnam-traffic.sqlite")
            if (UserDefaults.standard.string(forKey: "trafficDataVersion") ?? "").hasPrefix("traffic-v4-"), fm.fileExists(atPath: updated.path) { return updated }
        }
        return Bundle.main.url(forResource: "vietnam-traffic", withExtension: "sqlite")
    }
    static func search(_ input: String) -> [OfflinePlace] {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "đ", with: "d")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
        guard normalized.count >= 2, let url = databaseURL() else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database = database { sqlite3_close(database) }
            return []
        }
        defer { sqlite3_close(database) }
        let sql = "SELECT osm_type, osm_id, name, latitude, longitude, kind FROM places WHERE normalized LIKE ? ESCAPE '\\' ORDER BY length(name), name LIMIT 30"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        let escaped = normalized.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        let value = "%" + escaped + "%"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, value, -1, transient)
        func text(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
        var results: [OfflinePlace] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(OfflinePlace(id: "\(text(0))-\(sqlite3_column_int64(statement, 1))", name: text(2), kind: text(5), latitude: sqlite3_column_double(statement, 3), longitude: sqlite3_column_double(statement, 4)))
        }
        return results
    }
}
