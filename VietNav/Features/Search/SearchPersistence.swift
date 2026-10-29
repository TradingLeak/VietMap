import Foundation
import GRDB

public struct FavoritePlace: Identifiable, Codable {
    public let id: String
    public let label: String
    public let place: SearchResult
    public init(id: String, label: String, place: SearchResult) { self.id = id; self.label = label; self.place = place }
}

/// SQLite riêng cho dữ liệu tìm kiếm: cache, lịch sử và yêu thích không thay đổi seed giao thông.
public actor SearchPersistence {
    public static let shared = SearchPersistence()
    private var dbQueue: DatabaseQueue?
    private let path: String?
    private let clock: () -> Date
    public init(path: String? = nil, clock: @escaping () -> Date = Date.init) { self.path = path; self.clock = clock }
    private func queue() throws -> DatabaseQueue {
        if let dbQueue { return dbQueue }
        let location: String
        if let path { location = path }
        else {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            location = base.appendingPathComponent("vietnav_search.sqlite").path
        }
        let queue = try DatabaseQueue(path: location)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_search") { db in
            try db.execute(sql: """
                CREATE TABLE search_cache (key TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL, cached_at REAL NOT NULL);
                CREATE TABLE recent_places (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL, selected_at REAL NOT NULL);
                CREATE TABLE favorite_places (id TEXT PRIMARY KEY NOT NULL, label TEXT NOT NULL, payload BLOB NOT NULL, saved_at REAL NOT NULL);
                """)
        }
        try migrator.migrate(queue)
        dbQueue = queue
        return queue
    }
    public func cached(key: String) throws -> [SearchResult]? {
        let now = clock().timeIntervalSince1970
        return try queue().read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT payload FROM search_cache WHERE key = ? AND cached_at <= ? AND cached_at > ?", arguments: [key, now, now - 7 * 86400]) else { return nil }
            let data: Data = row["payload"]
            return try JSONDecoder().decode([SearchResult].self, from: data)
        }
    }
    public func cache(_ results: [SearchResult], key: String) throws {
        let data = try JSONEncoder().encode(results), now = clock().timeIntervalSince1970
        try queue().write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO search_cache(key,payload,cached_at) VALUES(?,?,?)", arguments: [key, data, now])
            try db.execute(sql: "DELETE FROM search_cache WHERE key NOT IN (SELECT key FROM search_cache ORDER BY cached_at DESC LIMIT 256)")
            // Chỉ xóa cache, không đụng lịch sử/yêu thích; giới hạn là tổng payload, không phải kích thước file SQLite.
            let bytes = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(length(payload)), 0) FROM search_cache") ?? 0
            if bytes > 50 * 1024 * 1024 { try db.execute(sql: "DELETE FROM search_cache") }
        }
    }
    public func addRecent(_ result: SearchResult) throws {
        let data = try JSONEncoder().encode(result), now = clock().timeIntervalSince1970
        try queue().write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO recent_places(id,payload,selected_at) VALUES(?,?,?)", arguments: [result.id, data, now])
            try db.execute(sql: "DELETE FROM recent_places WHERE id NOT IN (SELECT id FROM recent_places ORDER BY selected_at DESC LIMIT 20)")
        }
    }
    public func recent() throws -> [SearchResult] {
        try queue().read { db in
            try Row.fetchAll(db, sql: "SELECT payload FROM recent_places ORDER BY selected_at DESC").map { row in
                let data: Data = row["payload"]; return try JSONDecoder().decode(SearchResult.self, from: data)
            }
        }
    }
    public func clearRecent() throws { try queue().write { db in try db.execute(sql: "DELETE FROM recent_places") } }
    public func saveFavorite(_ favorite: FavoritePlace) throws {
        let data = try JSONEncoder().encode(favorite.place), now = clock().timeIntervalSince1970
        try queue().write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO favorite_places(id,label,payload,saved_at) VALUES(?,?,?,?)", arguments: [favorite.id, favorite.label, data, now])
        }
    }
    public func removeFavorite(id: String) throws { try queue().write { db in try db.execute(sql: "DELETE FROM favorite_places WHERE id = ?", arguments: [id]) } }
    public func favorites() throws -> [FavoritePlace] {
        try queue().read { db in
            try Row.fetchAll(db, sql: "SELECT id,label,payload FROM favorite_places ORDER BY saved_at DESC").map { row in
                let data: Data = row["payload"]
                return FavoritePlace(id: row["id"], label: row["label"], place: try JSONDecoder().decode(SearchResult.self, from: data))
            }
        }
    }
}
