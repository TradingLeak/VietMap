import XCTest
import SQLite3
@testable import VietNavCore

final class OfflineMapTests: XCTestCase {
    func testPrepareRasterAndVectorMBTiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("raster.mbtiles")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE metadata (name TEXT, value TEXT);
        CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
        INSERT INTO metadata VALUES ('format','png');
        INSERT INTO tiles VALUES (0,0,0,X'89504e47');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let style = try OfflineMapStore.prepare(path)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: style)) as? [String: Any])
        let sources = try XCTUnwrap(json["sources"] as? [String: [String: Any]])
        let uri = try XCTUnwrap(sources["offline"]?["url"] as? String)
        XCTAssertTrue(uri.hasPrefix("mbtiles:///"))
        let tileURL = try XCTUnwrap(URL(string: uri.replacingOccurrences(of: "mbtiles://", with: "file://")))
        defer { try? FileManager.default.removeItem(at: style); try? FileManager.default.removeItem(at: tileURL) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tileURL.path))
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE metadata SET value='pbf' WHERE name='format'", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let vectorStyle = try OfflineMapStore.prepare(path)
        defer { try? FileManager.default.removeItem(at: vectorStyle) }
        let vectorJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: vectorStyle)) as? [String: Any])
        let vectorSources = try XCTUnwrap(vectorJSON["sources"] as? [String: [String: Any]])
        XCTAssertEqual(vectorSources["offline"]?["type"] as? String, "vector")
        if let string = vectorSources["offline"]?["url"] as? String,
           let copied = URL(string: string.replacingOccurrences(of: "mbtiles://", with: "file://")) {
            try? FileManager.default.removeItem(at: copied)
        }
    }
}
