import Foundation
import GRDB
import SwiftUI

/// Chỉ nhập MBTiles raster có sẵn; không tải hàng loạt từ tile.openstreetmap.org.
@MainActor
final class OfflineMapStore: ObservableObject {
    static let shared = OfflineMapStore()
    @Published private(set) var styleURL: URL?
    @Published private(set) var isEnabled = false
    @Published private(set) var isImporting = false
    @Published var message: String?
    private let defaults = UserDefaults.standard
    private let styleKey = "vn.offline.style"
    private let enabledKey = "vn.offline.enabled"

    private init() {
        if let path = defaults.string(forKey: styleKey), FileManager.default.fileExists(atPath: path) {
            styleURL = URL(fileURLWithPath: path)
            isEnabled = defaults.bool(forKey: enabledKey)
        } else {
            defaults.set(false, forKey: enabledKey)
        }
    }
    func setEnabled(_ value: Bool) {
        guard !value || styleURL != nil else { message = "Hãy nhập tệp bản đồ MBTiles trước."; return }
        isEnabled = value
        defaults.set(value, forKey: enabledKey)
    }
    func importFile(_ source: URL) {
        guard !isImporting else { return }
        isImporting = true; message = nil
        let accessible = source.startAccessingSecurityScopedResource()
        Task {
            defer { if accessible { source.stopAccessingSecurityScopedResource() }; isImporting = false }
            do {
                let result = try await Task.detached(priority: .utility) { try Self.prepare(source) }.value
                styleURL = result; defaults.set(result.path, forKey: styleKey)
                setEnabled(true)
                message = "Đã nhập bản đồ. Chỉ hiển thị khu vực và mức zoom có trong tệp."
            } catch { message = "Không thể nhập bản đồ: \(error.localizedDescription)" }
        }
    }
    /// Sao chép file trước khi mở SQLite; không giữ file provider / security-scoped URL.
    nonisolated static func prepare(_ source: URL) throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("OfflineMaps", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let tiles = base.appendingPathComponent("\(id).mbtiles")
        let style = base.appendingPathComponent("\(id).json")
        do {
            try fm.copyItem(at: source, to: tiles)
            var config = Configuration(); config.readonly = true
            let queue = try DatabaseQueue(path: tiles.path, configuration: config)
            let format = try queue.read { db -> String in
                guard try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok",
                      let format = try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name='format' LIMIT 1")?.lowercased(),
                      ["png", "jpg", "jpeg", "pbf"].contains(format),
                      try Int.fetchOne(db, sql: "SELECT 1 FROM tiles LIMIT 1") == 1 else {
                    throw OfflineMapError.unsupported
                }
                return format
            }
            // `mbtiles:///...` do MapLibre Native đọc trực tiếp từ filesystem.
            let tileURL = tiles.absoluteString.replacingOccurrences(of: "file://", with: "mbtiles://")
            let layers: [[String: Any]]
            if format == "pbf" {
                // OpenMapTiles: không có glyphs/label online, nên chưa hiển thị tên đường offline.
                layers = [
                    ["id": "background", "type": "background", "paint": ["background-color": "#eef1e8"]],
                    ["id": "landuse", "type": "fill", "source": "offline", "source-layer": "landuse", "paint": ["fill-color": "#dcebd9"]],
                    ["id": "water", "type": "fill", "source": "offline", "source-layer": "water", "paint": ["fill-color": "#a9dce7"]],
                    ["id": "waterway", "type": "line", "source": "offline", "source-layer": "waterway", "paint": ["line-color": "#a9dce7", "line-width": 1.5]],
                    ["id": "building", "type": "fill", "source": "offline", "source-layer": "building", "paint": ["fill-color": "#dfd9cf"]],
                    ["id": "roads", "type": "line", "source": "offline", "source-layer": "transportation", "paint": ["line-color": "#fdfbf6", "line-width": 2.0]]
                ]
            } else {
                layers = [["id": "offline", "type": "raster", "source": "offline"]]
            }
            var source: [String: Any] = ["type": format == "pbf" ? "vector" : "raster", "url": tileURL,
                                         "attribution": "© OpenStreetMap contributors"]
            if format != "pbf" { source["tileSize"] = 256 }
            let json: [String: Any] = ["version": 8, "name": "VietNav offline", "sources": ["offline": source], "layers": layers]
            try JSONSerialization.data(withJSONObject: json).write(to: style, options: .atomic)
            return style
        } catch {
            try? fm.removeItem(at: tiles); try? fm.removeItem(at: style)
            throw error
        }
    }
}
private enum OfflineMapError: LocalizedError {
    case unsupported
    var errorDescription: String? { "Cần MBTiles raster PNG/JPEG hoặc vector PBF hợp lệ và có ít nhất một tile; PMTiles chưa hỗ trợ." }
}
