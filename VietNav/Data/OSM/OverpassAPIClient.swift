import Foundation
import CryptoKit

public struct BoundingBox: Codable, Equatable, Sendable {
    public let south: Double, west: Double, north: Double, east: Double
    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south; self.west = west; self.north = north; self.east = east
    }
    public func validate() throws {
        guard south.isFinite, west.isFinite, north.isFinite, east.isFinite,
              south >= -90, north <= 90, west >= -180, east <= 180,
              south < north, west < east else { throw OverpassError.invalidBoundingBox }
    }
    fileprivate var queryValue: String {
        [south, west, north, east].map { String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined(separator: ",")
    }
}

public struct VietnamRegion: Codable, Sendable {
    public let name: String
    public let bbox: BoundingBox
    public init(name: String, bbox: BoundingBox) { self.name = name; self.bbox = bbox }
}
public struct VietnamRegions: Codable, Sendable {
    public let description: String
    public let source: String
    public let regions: [VietnamRegion]
}
public struct Coordinate: Codable, Equatable, Sendable {
    public let lat: Double
    public let lon: Double
}
public struct OSMNode: Codable, Equatable, Sendable {
    public let id: Int64
    public let lat: Double
    public let lon: Double
    public let tags: [String: String]
    private enum CodingKeys: String, CodingKey { case id, lat, lon, tags }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        tags = try c.decodeIfPresent([String: String].self, forKey: .tags) ?? [:]
    }
}
public struct OSMWay: Codable, Equatable, Sendable {
    public let id: Int64
    public let nodes: [Int64]
    public let geometry: [Coordinate]?
    public let tags: [String: String]
    private enum CodingKeys: String, CodingKey { case id, nodes, geometry, tags }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        nodes = try c.decodeIfPresent([Int64].self, forKey: .nodes) ?? []
        geometry = try c.decodeIfPresent([Coordinate].self, forKey: .geometry)
        tags = try c.decodeIfPresent([String: String].self, forKey: .tags) ?? [:]
    }
}
public enum OSMElement: Codable, Equatable, Sendable {
    case node(OSMNode), way(OSMWay)
    private enum Keys: String, CodingKey { case type }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "node": self = .node(try OSMNode(from: decoder))
        case "way": self = .way(try OSMWay(from: decoder))
        default: throw OverpassError.unsupportedElement
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .node(let node):
            try node.encode(to: encoder)
            var c = encoder.container(keyedBy: Keys.self); try c.encode("node", forKey: .type)
        case .way(let way):
            try way.encode(to: encoder)
            var c = encoder.container(keyedBy: Keys.self); try c.encode("way", forKey: .type)
        }
    }
    fileprivate var identity: String {
        switch self { case .node(let n): return "node/\(n.id)"; case .way(let w): return "way/\(w.id)" }
    }
}
public enum OverpassError: Error {
    case invalidBoundingBox, missingRegions, unsupportedElement, invalidResponse, serverRemark(String), httpStatus(Int), invalidEndpoint
}
private struct OverpassResponse: Decodable {
    let elements: [OSMElement]?
    let remark: String?
}

/// Giới hạn trong tiến trình: tối đa hai request và cách nhau ít nhất hai giây.
private actor RequestGate {
    private var active = 0
    private var nextStart: TimeInterval = 0
    func acquire() async throws {
        while true {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            if active < 2 && now >= nextStart {
                active += 1
                nextStart = now + 2
                return
            }
            let delay = max(0.05, min(0.25, nextStart - now))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
    func release() { active -= 1 }
}

private actor ResponseCache {
    private let directory: URL
    private let ttl: TimeInterval = 7 * 24 * 60 * 60
    init(directory: URL) { self.directory = directory }
    private func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
    func get(_ key: String) -> Data? {
        let file = url(for: key)
        guard let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(date) >= 0, Date().timeIntervalSince(date) < ttl else { return nil }
        return try? Data(contentsOf: file)
    }
    func put(_ data: Data, key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: key), options: .atomic)
    }
    func remove(_ key: String) { try? FileManager.default.removeItem(at: url(for: key)) }
}

/// API công cộng có quota thay đổi; không dùng làm nguồn cập nhật liên tục trong app.
public final class OverpassAPIClient {
    public static let defaultEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    private let endpoint: URL
    private let session: URLSession
    private let regions: [VietnamRegion]
    private static let sharedGate = RequestGate()
    private let cache: ResponseCache
    private let maxAttempts: Int

    public init(regions: [VietnamRegion], endpoint: URL = defaultEndpoint, session: URLSession = .shared,
                cacheDirectory: URL? = nil, maxAttempts: Int = 4) {
        self.regions = regions
        self.endpoint = endpoint
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        cache = ResponseCache(directory: cacheDirectory ?? base.appendingPathComponent("VietNav/Overpass", isDirectory: true))
        self.maxAttempts = max(1, maxAttempts)
    }

    public func fetchSpeedCameras() async throws -> [OSMNode] {
        try await nationalNodes(filters: ["[\"highway\"=\"speed_camera\"]", "[\"enforcement\"=\"maxspeed\"]"])
    }
    public func fetchTrafficSignals() async throws -> [OSMNode] {
        try await nationalNodes(filters: ["[\"highway\"=\"traffic_signals\"][\"traffic_signals:camera\"=\"yes\"]", "[\"enforcement\"=\"traffic_signals\"]"])
    }
    public func fetchTollBooths() async throws -> [OSMNode] {
        try await nationalNodes(filters: ["[\"barrier\"=\"toll_booth\"]", "[\"highway\"=\"toll_gantry\"]"])
    }
    public func fetchRailwayCrossings() async throws -> [OSMNode] {
        try await nationalNodes(filters: ["[\"railway\"=\"level_crossing\"]"])
    }
    public func fetchResidentialZones() async throws -> [OSMElement] {
        try await national(selectors: [("node", "[\"traffic_sign\"~\"city_limit\"]"), ("way", "[\"zone:traffic\"=\"VN:urban\"]")], timeout: 300)
    }
    public func fetchSpeedLimits(bbox: BoundingBox) async throws -> [OSMWay] {
        try bbox.validate()
        let elements = try await execute(query(bbox: bbox, selectors: [("way", "[\"highway\"][\"maxspeed\"]")], timeout: 600))
        return elements.compactMap { if case .way(let w) = $0 { return w }; return nil }
    }
    private func nationalNodes(filters: [String]) async throws -> [OSMNode] {
        let elements = try await national(selectors: filters.map { ("node", $0) }, timeout: 300)
        return elements.compactMap { if case .node(let n) = $0 { return n }; return nil }
    }
    private func national(selectors: [(String, String)], timeout: Int) async throws -> [OSMElement] {
        guard !regions.isEmpty else { throw OverpassError.missingRegions }
        var unique: [String: OSMElement] = [:]
        // Tuần tự theo tỉnh để giảm tải server, trùng bbox được loại bằng type/id.
        for region in regions {
            try Task.checkCancellation()
            try region.bbox.validate()
            for element in try await execute(query(bbox: region.bbox, selectors: selectors, timeout: timeout)) {
                unique[element.identity] = element
            }
        }
        return unique.keys.sorted().compactMap { unique[$0] }
    }
    private func query(bbox: BoundingBox, selectors: [(String, String)], timeout: Int) -> String {
        let parts = selectors.map { "\($0.0)(area.vn)(\(bbox.queryValue))\($0.1);" }.joined()
        // Bbox giao area quốc gia để tránh trả về dữ liệu nước láng giềng.
        return "[out:json][timeout:\(timeout)];area[\"ISO3166-1\"=\"VN\"][\"admin_level\"=\"2\"]->.vn;(\(parts));out body geom;"
    }
    private func decode(_ data: Data) throws -> [OSMElement] {
        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)
        if let remark = response.remark { throw OverpassError.serverRemark(remark) }
        guard let elements = response.elements else { throw OverpassError.invalidResponse }
        return elements
    }
    private func execute(_ query: String) async throws -> [OSMElement] {
        guard endpoint.scheme == "https" || endpoint.scheme == "http" else { throw OverpassError.invalidEndpoint }
        let key = endpoint.absoluteString + "\n" + query
        if let data = await cache.get(key) {
            if let elements = try? decode(data) { return elements }
            await cache.remove(key)
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 660)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("VietNav-OSMDataFetcher/1.0", forHTTPHeaderField: "User-Agent")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            do {
                try await Self.sharedGate.acquire()
                let result: (Data, URLResponse)
                do { result = try await session.data(for: request) }
                catch { await Self.sharedGate.release(); throw error }
                await Self.sharedGate.release()
                guard let http = result.1 as? HTTPURLResponse else { throw OverpassError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else {
                    if [429, 500, 502, 503, 504].contains(http.statusCode), attempt + 1 < maxAttempts {
                        let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0
                        try await backoff(attempt, minimum: retryAfter)
                        continue
                    }
                    throw OverpassError.httpStatus(http.statusCode)
                }
                let elements = try decode(result.0) // Không cache phản hồi lỗi hoặc thiếu dữ liệu.
                try await cache.put(result.0, key: key)
                return elements
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                guard attempt + 1 < maxAttempts, [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(error.code) else { throw error }
                try await backoff(attempt)
            } catch let error as OverpassError {
                if case .serverRemark = error, attempt + 1 < maxAttempts { try await backoff(attempt); continue }
                throw error
            }
        }
        throw OverpassError.invalidResponse
    }
    private func backoff(_ attempt: Int, minimum: Double = 0) async throws {
        let seconds = max(minimum.isFinite ? min(max(0, minimum), 3600) : 0, min(60, pow(2, Double(attempt + 1))))
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
