import Foundation
import GRDB

public enum NodeType: String, Codable, CaseIterable {
    case speedCamera = "SPEED_CAMERA", redLightCamera = "RED_LIGHT_CAMERA"
    case speedLimit = "SPEED_LIMIT", residentialIn = "RESIDENTIAL_IN", residentialOut = "RESIDENTIAL_OUT"
    case tollBooth = "TOLL_BOOTH", railwayCrossing = "RAILWAY_CROSSING", noOvertaking = "NO_OVERTAKING"
    case incident = "INCIDENT"
}

public struct TrafficNode: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "traffic_nodes"
    public var id: Int64?
    public var osmID: Int64?
    public var type: NodeType
    public var latitude: Double
    public var longitude: Double
    public var speedLimit: Int?
    public var bearing: Double?
    public var roadName: String?
    public var roadRef: String?
    public var province: String?
    public var district: String?
    public var verified: Bool
    public var source: String
    public var createdAt: Int64?
    public var updatedAt: Int64?

    public init(id: Int64? = nil, osmID: Int64? = nil, type: NodeType, latitude: Double, longitude: Double,
                speedLimit: Int? = nil, bearing: Double? = nil, roadName: String? = nil, roadRef: String? = nil,
                province: String? = nil, district: String? = nil, verified: Bool = false, source: String = "OSM",
                createdAt: Int64? = nil, updatedAt: Int64? = nil) {
        self.id = id; self.osmID = osmID; self.type = type; self.latitude = latitude; self.longitude = longitude
        self.speedLimit = speedLimit; self.bearing = bearing; self.roadName = roadName; self.roadRef = roadRef
        self.province = province; self.district = district; self.verified = verified; self.source = source
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
    enum CodingKeys: String, CodingKey {
        case id, type, latitude, longitude, bearing, province, district, verified, source
        case osmID = "osm_id", speedLimit = "speed_limit", roadName = "road_name", roadRef = "road_ref"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

public struct UserReport: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "user_reports"
    public var id: Int64?
    public var type: NodeType
    public var latitude: Double?
    public var longitude: Double?
    public var description: String?
    public var photoPath: String?
    public var reportedAt: Int64?
    public var uploaded: Bool
    public init(id: Int64? = nil, type: NodeType, latitude: Double? = nil, longitude: Double? = nil,
                description: String? = nil, photoPath: String? = nil, reportedAt: Int64? = nil, uploaded: Bool = false) {
        self.id = id; self.type = type; self.latitude = latitude; self.longitude = longitude
        self.description = description; self.photoPath = photoPath; self.reportedAt = reportedAt; self.uploaded = uploaded
    }
    enum CodingKeys: String, CodingKey {
        case id, type, latitude, longitude, description, uploaded
        case photoPath = "photo_path", reportedAt = "reported_at"
    }
}

/// Tọa độ GeoJSON theo thứ tự longitude, latitude.
public struct RoadCoordinate: Equatable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}
public struct RoadSegment {
    public var id: Int64?
    public var osmWayID: Int64?
    public var roadName: String?
    public var roadType: String?
    public var maxSpeed: Int?
    public var coordinates: [RoadCoordinate]
    public var province: String?
    public init(id: Int64? = nil, osmWayID: Int64? = nil, roadName: String? = nil, roadType: String? = nil,
                maxSpeed: Int? = nil, coordinates: [RoadCoordinate], province: String? = nil) {
        self.id = id; self.osmWayID = osmWayID; self.roadName = roadName; self.roadType = roadType
        self.maxSpeed = maxSpeed; self.coordinates = coordinates; self.province = province
    }
}
