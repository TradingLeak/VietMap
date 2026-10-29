import Foundation
import CryptoKit
import SQLite3

/// Validate downloaded files before replacing the active offline database.
enum TrafficDatabaseValidator {
    enum ValidationError: LocalizedError {
        case invalidFile
        var errorDescription: String? { "Tệp dữ liệu sai kích thước, checksum hoặc cấu trúc." }
    }
    static func validate(url: URL, expectedSize: Int64, expectedHash: String) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attrs[.size] as? NSNumber)?.int64Value == expectedSize else { throw ValidationError.invalidFile }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 16) == Data("SQLite format 3\0".utf8) else { throw ValidationError.invalidFile }
        try handle.seek(toOffset: 0)
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { digest.update(data: chunk) }
        guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == expectedHash.lowercased() else { throw ValidationError.invalidFile }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            throw ValidationError.invalidFile
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK else { throw ValidationError.invalidFile }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let result = sqlite3_column_text(stmt, 0), String(cString: result) == "ok" else { throw ValidationError.invalidFile }
        // Check the columns relied on by offline search, not just the SQLite header.
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT osm_type, osm_id, name, normalized, latitude, longitude, kind FROM places LIMIT 0", -1, &schema, nil) == SQLITE_OK else { throw ValidationError.invalidFile }
        sqlite3_finalize(schema)
        var features: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT osm_type, osm_id, category, latitude, longitude, tags, geometry FROM features LIMIT 0", -1, &features, nil) == SQLITE_OK else { throw ValidationError.invalidFile }
        sqlite3_finalize(features)
        for sql in ["SELECT osm_id, tags, nodes FROM road_ways LIMIT 0", "SELECT osm_id, tags, members FROM turn_restrictions LIMIT 0", "SELECT osm_id, tags, members FROM enforcement_relations LIMIT 0"] {
            var table: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &table, nil) == SQLITE_OK else { throw ValidationError.invalidFile }
            sqlite3_finalize(table)
        }
    }
}
