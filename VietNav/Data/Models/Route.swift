import Foundation
import CoreLocation
import OSMData

public struct Route {
    public let id: UUID
    public let geometry: [CLLocationCoordinate2D]
    public let distance: Double // mét
    public let duration: TimeInterval // giây
    public let steps: [RouteStep]
    public let bbox: BoundingBox
    public let profile: RouteProfile
    public let waypoints: [CLLocationCoordinate2D]
    public let destination: CLLocationCoordinate2D?

    public init(id: UUID = UUID(), geometry: [CLLocationCoordinate2D], distance: Double,
                duration: TimeInterval, steps: [RouteStep], bbox: BoundingBox, profile: RouteProfile = .car,
                waypoints: [CLLocationCoordinate2D] = [], destination: CLLocationCoordinate2D? = nil) {
        self.id = id; self.geometry = geometry; self.distance = distance
        self.duration = duration; self.steps = steps; self.bbox = bbox
        self.profile = profile; self.waypoints = waypoints; self.destination = destination
    }
}

public struct RouteStep {
    public let instruction: String
    public let distance: Double
    public let duration: TimeInterval
    public let maneuver: Maneuver
    public let streetName: String
    public let coordinate: CLLocationCoordinate2D
    public let lanes: [LaneGuidance]

    public init(instruction: String, distance: Double, duration: TimeInterval, maneuver: Maneuver,
                streetName: String, coordinate: CLLocationCoordinate2D, lanes: [LaneGuidance] = []) {
        self.instruction = instruction; self.distance = distance; self.duration = duration
        self.maneuver = maneuver; self.streetName = streetName; self.coordinate = coordinate; self.lanes = lanes
    }
}

public enum Maneuver: Equatable {
    case turnLeft, turnRight, slightLeft, slightRight, straight, uTurn, roundabout, exitRoundabout, arrive, depart
    case unknown
}

/// valid == nil: tag OSM thô không đủ thông tin để khuyến nghị làn.
public struct LaneGuidance: Equatable {
    public let indications: [String]
    public let valid: Bool?
    public init(indications: [String], valid: Bool? = nil) { self.indications = indications; self.valid = valid }

    public static func parseOSMTurnLanes(_ value: String) -> [LaneGuidance] {
        value.split(separator: "|", omittingEmptySubsequences: false).map { lane in
            LaneGuidance(indications: lane.split(separator: ";", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }
    }
}
