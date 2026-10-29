import SwiftUI
import CoreLocation
import SQLite3

private struct RoadLine {
    let points: [CLLocationCoordinate2D]
    let major: Bool
}
private struct RoadResult {
    let roads: [RoadLine]
    let truncated: Bool
}

/// A limited 2D offline road sketch, not a complete basemap or navigation tool.
private enum RoadProjection {
    static func world(_ point: CLLocationCoordinate2D) -> CGPoint {
        let lat = min(85, max(-85, point.latitude)) * .pi / 180
        return CGPoint(x: (point.longitude + 180) / 360,
                       y: (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2)
    }
    static func coordinate(_ point: CGPoint) -> CLLocationCoordinate2D {
        let x = min(1, max(0, Double(point.x)))
        let y = min(1, max(0, Double(point.y)))
        return CLLocationCoordinate2D(latitude: atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi,
                                      longitude: x * 360 - 180)
    }
    static func scale(_ zoom: Double) -> Double { 256 * pow(2, zoom) }
}

private enum OfflineRoadReader {
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Không đọc được dữ liệu đường offline." }
    }
    static func read(center: CLLocationCoordinate2D, zoom: Double, size: CGSize) throws -> RoadResult {
        guard let url = OfflinePlaceSearch.databaseURL() else { throw Failure.unavailable }
        let middle = RoadProjection.world(center)
        let scale = RoadProjection.scale(zoom)
        let dx = Double(size.width) / scale * 0.7
        let dy = Double(size.height) / scale * 0.7
        let northwest = RoadProjection.coordinate(CGPoint(x: Double(middle.x) - dx, y: Double(middle.y) - dy))
        let southeast = RoadProjection.coordinate(CGPoint(x: Double(middle.x) + dx, y: Double(middle.y) + dy))
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            throw Failure.unavailable
        }
        defer { sqlite3_close(db) }
        let sql = """
          SELECT w.nodes, w.tags FROM road_bounds b JOIN road_ways w ON w.osm_id = b.id
          WHERE b.min_lon <= ? AND b.max_lon >= ? AND b.min_lat <= ? AND b.max_lat >= ? LIMIT 2501
          """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw Failure.unavailable }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, southeast.longitude)
        sqlite3_bind_double(statement, 2, northwest.longitude)
        sqlite3_bind_double(statement, 3, northwest.latitude)
        sqlite3_bind_double(statement, 4, southeast.latitude)
        var lines: [RoadLine] = []
        var pointCount = 0
        var truncated = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if lines.count >= 2500 || pointCount >= 100_000 { truncated = true; break }
            let length = Int(sqlite3_column_bytes(statement, 0))
            guard length >= 32, length % 16 == 0, length <= 1_600_000,
                  let raw = sqlite3_column_blob(statement, 0),
                  let rawTags = sqlite3_column_text(statement, 1) else { continue }
            let bytes = raw.assumingMemoryBound(to: UInt8.self)
            func word(_ offset: Int) -> UInt32 {
                UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) |
                (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
            }
            var points: [CLLocationCoordinate2D] = []
            points.reserveCapacity(length / 16)
            for offset in stride(from: 0, to: length, by: 16) {
                let lon = Double(Int32(bitPattern: word(offset + 8))) / 10_000_000
                let lat = Double(Int32(bitPattern: word(offset + 12))) / 10_000_000
                guard abs(lat) <= 90, abs(lon) <= 180 else { continue }
                points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            guard points.count >= 2 else { continue }
            pointCount += points.count
            let data = Data(String(cString: rawTags).utf8)
            let tags = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            let major = ["motorway", "trunk", "primary", "secondary", "tertiary"].contains(tags?["highway"] ?? "")
            lines.append(RoadLine(points: points, major: major))
        }
        return RoadResult(roads: lines, truncated: truncated)
    }
}

struct OfflineRoadCanvas: View {
    @ObservedObject var model: MapModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var roads: [RoadLine] = []
    @State private var note = "Đang tải đường offline…"
    @GestureState private var drag = CGSize.zero

    private var center: CLLocationCoordinate2D {
        model.followsLocation ? (model.location?.coordinate ?? model.mapCenter) : model.mapCenter
    }
    var body: some View {
        GeometryReader { proxy in
            let current = center
            let origin = RoadProjection.world(current)
            let scale = RoadProjection.scale(model.zoom)
            let key = "\(Int(current.latitude * 10000)):\(Int(current.longitude * 10000)):\(model.zoom):\(Int(proxy.size.width)):\(Int(proxy.size.height))"
            ZStack(alignment: .top) {
                (colorScheme == .dark ? Color(red: 0.09, green: 0.12, blue: 0.16) : Color(red: 0.91, green: 0.93, blue: 0.89))
                Canvas { context, size in
                    func screen(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
                        let p = RoadProjection.world(coordinate)
                        return CGPoint(x: size.width / 2 + (p.x - origin.x) * scale + drag.width,
                                       y: size.height / 2 + (p.y - origin.y) * scale + drag.height)
                    }
                    for road in roads {
                        guard let first = road.points.first else { continue }
                        var path = Path(); path.move(to: screen(first))
                        for point in road.points.dropFirst() { path.addLine(to: screen(point)) }
                        context.stroke(path, with: .color(road.major ? .orange.opacity(0.9) : (colorScheme == .dark ? .white.opacity(0.65) : .white)), style: StrokeStyle(lineWidth: road.major ? 3 : 2, lineCap: .round, lineJoin: .round))
                    }
                    if let location = model.location {
                        let point = screen(location.coordinate)
                        let circle = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                        context.fill(Path(ellipseIn: circle), with: .color(.blue))
                        context.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: 2)
                    }
                }
                Text(note).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 12)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 5)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    let point = RoadProjection.world(current)
                    model.followsLocation = false
                    model.mapCenter = RoadProjection.coordinate(CGPoint(x: Double(point.x) - value.translation.width / scale,
                                                                         y: Double(point.y) - value.translation.height / scale))
                })
            .task(id: key) {
                guard model.zoom >= 12 else { roads = []; note = "OSM OFFLINE · Phóng to để xem đường"; return }
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                let zoom = model.zoom, size = proxy.size
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try OfflineRoadReader.read(center: current, zoom: zoom, size: size)
                    }.value
                    guard !Task.isCancelled else { return }
                    roads = result.roads
                    note = result.truncated ? "OSM OFFLINE · Giới hạn số đường · Phóng to" : "OSM OFFLINE · Chỉ có đường · Chưa dẫn đường"
                } catch {
                    guard !Task.isCancelled else { return }
                    roads = []
                    note = error.localizedDescription
                }
            }
        }
        .accessibilityLabel("Bản đồ đường OSM offline thử nghiệm, chưa hỗ trợ dẫn đường")
    }
}
