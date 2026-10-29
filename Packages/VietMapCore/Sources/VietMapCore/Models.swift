import Foundation

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-85...85).contains(latitude) && (-180...180).contains(longitude)
    }

    public func distance(to other: Coordinate) -> Double { Geo.distance(self, other) }
}

public enum RoadDirection: String, Codable, Sendable {
    case both, forward, backward
}

public struct RoadSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var start: Coordinate
    public var end: Coordinate
    public var speedLimit: Int?
    public var direction: RoadDirection

    public init(id: String, name: String, start: Coordinate, end: Coordinate, speedLimit: Int?, direction: RoadDirection = .both) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.speedLimit = speedLimit
        self.direction = direction
    }
}

public enum HazardKind: String, CaseIterable, Codable, Sendable {
    case camera, speedLimit, residential, noOvertaking, toll, trafficLight, danger, restArea, tunnel

    public var title: String {
        switch self {
        case .camera: return "Camera giao thông"
        case .speedLimit: return "Giới hạn tốc độ"
        case .residential: return "Khu dân cư"
        case .noOvertaking: return "Cấm vượt"
        case .toll: return "Trạm thu phí"
        case .trafficLight: return "Đèn tín hiệu"
        case .danger: return "Đoạn đường nguy hiểm"
        case .restArea: return "Trạm dừng nghỉ"
        case .tunnel: return "Đường hầm"
        }
    }

    public var symbol: String {
        switch self {
        case .camera: return "camera.fill"
        case .speedLimit: return "speedometer"
        case .residential: return "building.2.fill"
        case .noOvertaking: return "car.2.fill"
        case .toll: return "creditcard.fill"
        case .trafficLight: return "light.beacon.max.fill"
        case .danger: return "exclamationmark.triangle.fill"
        case .restArea: return "cup.and.saucer.fill"
        case .tunnel: return "mountain.2.fill"
        }
    }
}

public struct TrafficHazard: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: HazardKind
    public var name: String
    public var coordinate: Coordinate
    /// Vehicle travel bearing in degrees, not the optical facing direction of a camera.
    public var heading: Double?
    public var speedLimit: Int?
    public var roadID: String?
    public var isEnd: Bool

    public init(id: String, kind: HazardKind, name: String, coordinate: Coordinate, heading: Double? = nil, speedLimit: Int? = nil, roadID: String? = nil, isEnd: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.coordinate = coordinate
        self.heading = heading
        self.speedLimit = speedLimit
        self.roadID = roadID
        self.isEnd = isEnd
    }

    public var title: String { isEnd ? "Hết \(kind.title.lowercased())" : kind.title }
}

public struct DatasetSource: Codable, Equatable, Sendable {
    public var name: String
    public var url: String
    public var license: String
    public var attribution: String

    public init(name: String, url: String, license: String, attribution: String) {
        self.name = name
        self.url = url
        self.license = license
        self.attribution = attribution
    }
}

public struct TrafficDataset: Codable, Equatable, Sendable {
    public static let maximumBytes = 32 * 1_024 * 1_024
    public var schemaVersion: Int
    public var id: String
    public var version: String
    public var name: String
    public var updatedAt: Date
    public var source: DatasetSource
    public var isDemo: Bool
    public var roads: [RoadSegment]
    public var hazards: [TrafficHazard]

    public init(schemaVersion: Int = 1, id: String, version: String, name: String, updatedAt: Date, source: DatasetSource, isDemo: Bool, roads: [RoadSegment], hazards: [TrafficHazard]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.version = version
        self.name = name
        self.updatedAt = updatedAt
        self.source = source
        self.isDemo = isDemo
        self.roads = roads
        self.hazards = hazards
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw DatasetError.invalid("Phiên bản dữ liệu không được hỗ trợ.") }
        guard !id.isEmpty, id.count <= 128, !name.isEmpty, name.count <= 200, !version.isEmpty, version.count <= 64 else {
            throw DatasetError.invalid("Thông tin bộ dữ liệu không hợp lệ.")
        }
        guard !source.name.isEmpty, !source.license.isEmpty, !source.attribution.isEmpty,
              [source.name, source.license, source.attribution, source.url].allSatisfy({ $0.count <= 2_000 }),
              let url = URL(string: source.url), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            throw DatasetError.invalid("Cần khai báo nguồn, URL HTTPS, giấy phép và ghi công dữ liệu.")
        }
        guard roads.count <= 100_000, hazards.count <= 100_000, !(roads.isEmpty && hazards.isEmpty) else {
            throw DatasetError.invalid("Bộ dữ liệu rỗng hoặc vượt 100.000 đường / 100.000 điểm.")
        }
        var roadIDs = Set<String>()
        for road in roads {
            guard !road.id.isEmpty, road.id.count <= 128, roadIDs.insert(road.id).inserted,
                  road.name.count <= 200, road.start.isValid, road.end.isValid,
                  abs(road.start.longitude - road.end.longitude) <= 1,
                  (1...5_000).contains(road.start.distance(to: road.end)), Self.validLimit(road.speedLimit) else {
                throw DatasetError.invalid("Đoạn đường không hợp lệ hoặc trùng ID: \(road.id.prefix(60)).")
            }
        }
        var hazardIDs = Set<String>()
        for hazard in hazards {
            guard !hazard.id.isEmpty, hazard.id.count <= 128, hazardIDs.insert(hazard.id).inserted,
                  hazard.name.count <= 200, hazard.coordinate.isValid, Self.validLimit(hazard.speedLimit),
                  hazard.heading.map({ $0.isFinite && (0..<360).contains($0) }) ?? true,
                  hazard.roadID.map({ roadIDs.contains($0) }) ?? true else {
                throw DatasetError.invalid("Điểm cảnh báo không hợp lệ hoặc trùng ID: \(hazard.id.prefix(60)).")
            }
        }
    }

    public static func decode(_ data: Data) throws -> TrafficDataset {
        guard data.count <= maximumBytes else { throw DatasetError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dataset = try decoder.decode(TrafficDataset.self, from: data)
        try dataset.validate()
        return dataset
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private static func validLimit(_ limit: Int?) -> Bool { limit.map { (5...160).contains($0) } ?? true }
}

public enum DatasetError: LocalizedError, Equatable {
    case invalid(String)
    case tooLarge
    case checksumMismatch
    case insecureURL
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .tooLarge: return "Tệp vượt giới hạn 32 MB. Hãy chia dữ liệu theo khu vực."
        case .checksumMismatch: return "SHA-256 không khớp. Dữ liệu cũ vẫn được giữ nguyên."
        case .insecureURL: return "Chỉ chấp nhận URL HTTPS công khai, không chứa tài khoản hoặc mật khẩu."
        case .server(let code): return "Máy chủ trả về HTTP \(code). Dữ liệu chưa được thay đổi."
        }
    }
}

public struct LocationFix: Codable, Equatable, Sendable {
    public var coordinate: Coordinate
    public var speedMPS: Double?
    public var heading: Double?
    public var horizontalAccuracy: Double
    public var timestamp: Date

    public init(coordinate: Coordinate, speedMPS: Double?, heading: Double?, horizontalAccuracy: Double, timestamp: Date) {
        self.coordinate = coordinate
        self.speedMPS = speedMPS
        self.heading = heading
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    public func isUsable(at date: Date) -> Bool {
        coordinate.isValid && horizontalAccuracy.isFinite && (0...50).contains(horizontalAccuracy)
            && (-2...10).contains(date.timeIntervalSince(timestamp))
    }

    public var validSpeedKmh: Double? {
        guard let speedMPS, speedMPS.isFinite, (0...85).contains(speedMPS) else { return nil }
        return speedMPS * 3.6
    }

    public var validHeading: Double? {
        guard let heading, heading.isFinite, (0..<360).contains(heading) else { return nil }
        return heading
    }
}
