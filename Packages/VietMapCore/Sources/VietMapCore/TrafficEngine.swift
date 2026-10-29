import Foundation

public struct EngineConfiguration: Equatable, Sendable {
    public var overspeedTolerance: Double
    public var maximumWarningDistance: Double
    public var enabledKinds: Set<HazardKind>

    public init(overspeedTolerance: Double = 3, maximumWarningDistance: Double = 500, enabledKinds: Set<HazardKind> = Set(HazardKind.allCases)) {
        self.overspeedTolerance = overspeedTolerance
        self.maximumWarningDistance = maximumWarningDistance
        self.enabledKinds = enabledKinds
    }

    var tolerance: Double { overspeedTolerance.isFinite ? min(10, max(0, overspeedTolerance)) : 3 }
    var warningCap: Double { maximumWarningDistance.isFinite ? min(800, max(150, maximumWarningDistance)) : 500 }
    public func lookahead(speedKmh: Double) -> Double { min(warningCap, max(150, speedKmh * 3)) }
}

public struct RoadMatch: Equatable, Sendable {
    public let road: RoadSegment
    public let coordinate: Coordinate
    public let forward: Bool
    public let distance: Double
}

public struct UpcomingHazard: Identifiable, Equatable, Sendable {
    public var id: String { hazard.id }
    public let hazard: TrafficHazard
    public let distance: Double
}

public struct DrivingSnapshot: Equatable, Sendable {
    public var speedKmh: Double?
    public var road: RoadSegment?
    public var speedLimit: Int?
    public var upcoming: [UpcomingHazard]
    public var isOverspeed: Bool
    public var isReliable: Bool
    public var timestamp: Date?

    public static let unavailable = DrivingSnapshot(speedKmh: nil, road: nil, speedLimit: nil, upcoming: [], isOverspeed: false, isReliable: false, timestamp: nil)
}

public struct Announcement: Equatable, Sendable {
    public let text: String
    public let priority: Int
    public init(text: String, priority: Int = 1) { self.text = text; self.priority = priority }
}

public struct EngineUpdate: Sendable {
    public let snapshot: DrivingSnapshot
    public let announcements: [Announcement]
}

/// Advisory only: never infers a legal limit from a camera or an upcoming sign.
/// Unknown/ambiguous roads and stale/inaccurate locations deliberately produce no limit.
public struct TrafficEngine: Sendable {
    public var configuration: EngineConfiguration
    public private(set) var dataset: TrafficDataset?
    public private(set) var snapshot = DrivingSnapshot.unavailable
    private var grid: SpatialGrid?
    private var lastTimestamp: Date?
    private var speedSamples: [Double] = []
    private var filteredSpeed: Double?
    private var candidateID: String?
    private var candidateCount = 0
    private var overspeedSince: Date?
    private var lastOverspeedSpeech: Date?
    private var announced: [String: Date] = [:]

    public init(configuration: EngineConfiguration = EngineConfiguration()) {
        self.configuration = configuration
    }

    public init(dataset: TrafficDataset, configuration: EngineConfiguration = EngineConfiguration()) throws {
        try dataset.validate()
        self.configuration = configuration
        self.dataset = dataset
        self.grid = SpatialGrid(dataset: dataset)
    }

    public func mapFeatures(near point: Coordinate, radius: Double = 1_500) -> (roads: [RoadSegment], hazards: [TrafficHazard]) {
        guard let dataset, let grid else { return ([], []) }
        let roads = grid.nearbyRoads(point, radius: radius).prefix(600).map { dataset.roads[$0] }
        let hazards = grid.nearbyHazards(point, radius: radius).map { dataset.hazards[$0] }
            .filter { $0.coordinate.distance(to: point) <= radius }
            .sorted { $0.coordinate.distance(to: point) < $1.coordinate.distance(to: point) }
        return (roads, Array(hazards.prefix(60)))
    }

    public mutating func invalidate() -> EngineUpdate {
        snapshot = .unavailable
        filteredSpeed = nil
        speedSamples.removeAll()
        candidateID = nil
        candidateCount = 0
        overspeedSince = nil
        return EngineUpdate(snapshot: snapshot, announcements: [])
    }

    public mutating func process(_ fix: LocationFix, now: Date) -> EngineUpdate {
        guard fix.isUsable(at: now) else { return invalidate() }
        if let lastTimestamp, fix.timestamp <= lastTimestamp {
            return EngineUpdate(snapshot: snapshot, announcements: [])
        }
        // A gap must not count as continuous overspeed or continuous road matching.
        if let lastTimestamp, fix.timestamp.timeIntervalSince(lastTimestamp) > 10 { _ = invalidate() }
        lastTimestamp = fix.timestamp
        let rawSpeed = fix.validSpeedKmh
        if let speed = rawSpeed {
            speedSamples.append(speed)
            if speedSamples.count > 3 { speedSamples.removeFirst() }
            let median = speedSamples.sorted()[speedSamples.count / 2]
            filteredSpeed = speed < 2 ? 0 : (filteredSpeed.map { $0 * 0.35 + median * 0.65 } ?? speed)
        } else {
            filteredSpeed = nil
            speedSamples.removeAll()
        }

        let match = roadMatch(for: fix)
        if let match, match.road.id == candidateID {
            candidateCount += 1
        } else {
            candidateID = match?.road.id
            candidateCount = match == nil ? 0 : 1
            overspeedSince = nil
        }
        let road = candidateCount >= 2 ? match?.road : nil
        let limit = road?.speedLimit
        var overspeed = snapshot.isOverspeed && snapshot.road?.id == road?.id
        var messages: [Announcement] = []
        if let speed = rawSpeed, let limit {
            let threshold = Double(limit) + configuration.tolerance
            if speed > threshold {
                if overspeedSince == nil { overspeedSince = fix.timestamp }
                if let since = overspeedSince, fix.timestamp.timeIntervalSince(since) >= 2 { overspeed = true }
            } else {
                overspeedSince = nil
                if speed <= max(Double(limit), threshold - 2) { overspeed = false }
            }
            if overspeed && (lastOverspeedSpeech.map { now.timeIntervalSince($0) >= 20 } ?? true) {
                messages.append(Announcement(text: "Bạn đang vượt tốc độ. Giới hạn đoạn đường là \(limit) ki lô mét một giờ.", priority: 3))
                lastOverspeedSpeech = now
            }
        } else {
            overspeed = false
            overspeedSince = nil
        }

        let upcoming = upcomingHazards(for: fix, match: match)
        announced = announced.filter { now.timeIntervalSince($0.value) < 600 }
        for item in upcoming.prefix(3) {
            let band = item.distance <= 100 ? "near" : "ahead"
            let key = "\(item.id):\(band)"
            guard announced[key] == nil else { continue }
            announced[key] = now
            // A close initial fix shouldn't queue two announcements for the same point.
            if band == "near" { announced["\(item.id):ahead"] = now }
            let metres = max(10, Int((item.distance / 10).rounded()) * 10)
            var text = "Còn \(metres) mét, \(item.hazard.title.lowercased())."
            if let speedLimit = item.hazard.speedLimit { text += " Biển báo \(speedLimit) ki lô mét một giờ." }
            messages.append(Announcement(text: text, priority: item.hazard.kind == .camera ? 2 : 1))
        }
        snapshot = DrivingSnapshot(speedKmh: filteredSpeed, road: road, speedLimit: limit, upcoming: upcoming, isOverspeed: overspeed, isReliable: true, timestamp: fix.timestamp)
        return EngineUpdate(snapshot: snapshot, announcements: messages.sorted { $0.priority > $1.priority })
    }

    private func roadMatch(for fix: LocationFix) -> RoadMatch? {
        guard let dataset, let grid, let heading = fix.validHeading,
              let speed = fix.validSpeedKmh, speed >= 5 else { return nil }
        var matches: [(RoadMatch, Double)] = []
        let maximumDistance = max(12, min(25, fix.horizontalAccuracy))
        for index in grid.nearbyRoads(fix.coordinate, radius: 70) {
            let road = dataset.roads[index]
            let projection = Geo.project(fix.coordinate, onto: road.start, road.end)
            guard projection.distance <= maximumDistance else { continue }
            let bearing = Geo.bearing(road.start, road.end)
            let forwardDifference = Geo.angleDifference(heading, bearing)
            let backwardDifference = Geo.angleDifference(heading, (bearing + 180).truncatingRemainder(dividingBy: 360))
            let forward: Bool
            switch road.direction {
            case .forward: forward = true
            case .backward: forward = false
            case .both: forward = forwardDifference <= backwardDifference
            }
            let difference = forward ? forwardDifference : backwardDifference
            guard difference <= 50 else { continue }
            let score = projection.distance + difference * 0.3
            matches.append((RoadMatch(road: road, coordinate: projection.coordinate, forward: forward, distance: projection.distance), score))
        }
        matches.sort { $0.1 == $1.1 ? $0.0.road.id < $1.0.road.id : $0.1 < $1.1 }
        guard let best = matches.first else { return nil }
        // Prefer "unknown" to a guessed limit on a parallel road or at a junction.
        if matches.count > 1 {
            let next = matches[1]
            if next.1 - best.1 < 7 && (next.0.road.speedLimit != best.0.road.speedLimit || next.0.road.name != best.0.road.name) { return nil }
        }
        return best.0
    }

    private struct PathLeg {
        let roadID: String
        let start: Coordinate
        let end: Coordinate
        let distanceBefore: Double
    }

    private func forwardPath(from match: RoadMatch, maximumDistance: Double) -> [PathLeg] {
        guard let dataset, let grid else { return [] }
        var legs: [PathLeg] = []
        var road = match.road
        var start = match.coordinate
        var end = match.forward ? road.end : road.start
        var distance = 0.0
        var visited = Set<String>()
        for _ in 0..<48 {
            guard visited.insert(road.id).inserted else { break }
            legs.append(PathLeg(roadID: road.id, start: start, end: end, distanceBefore: distance))
            distance += start.distance(to: end)
            if distance >= maximumDistance { break }
            let incoming = Geo.bearing(start, end)
            var next: [(RoadSegment, Coordinate, Double)] = []
            for index in grid.nearbyRoads(end, radius: 10) {
                let candidate = dataset.roads[index]
                guard !visited.contains(candidate.id) else { continue }
                if candidate.direction != .backward, candidate.start.distance(to: end) <= 3 {
                    let angle = Geo.angleDifference(incoming, Geo.bearing(candidate.start, candidate.end))
                    if angle < 75 { next.append((candidate, candidate.end, angle)) }
                }
                if candidate.direction != .forward, candidate.end.distance(to: end) <= 3 {
                    let angle = Geo.angleDifference(incoming, Geo.bearing(candidate.end, candidate.start))
                    if angle < 75 { next.append((candidate, candidate.start, angle)) }
                }
            }
            next.sort { $0.2 < $1.2 }
            guard let chosen = next.first else { break }
            if next.count > 1 && next[1].2 - chosen.2 < 15 { break }
            start = end
            end = chosen.1
            road = chosen.0
        }
        return legs
    }

    private func upcomingHazards(for fix: LocationFix, match: RoadMatch?) -> [UpcomingHazard] {
        guard let dataset, let grid, let heading = fix.validHeading,
              let speed = fix.validSpeedKmh, speed >= 5 else { return [] }
        let radius = configuration.lookahead(speedKmh: speed)
        let path = match.map { forwardPath(from: $0, maximumDistance: radius) } ?? []
        var result: [UpcomingHazard] = []
        for index in grid.nearbyHazards(fix.coordinate, radius: radius + 40) {
            let hazard = dataset.hazards[index]
            guard configuration.enabledKinds.contains(hazard.kind) else { continue }
            var alongDistance: Double?
            if path.isEmpty {
                // Without a road match, only point proximity is shown; no legal limit is inferred.
                guard hazard.roadID == nil else { continue }
                let offset = Geo.offset(from: fix.coordinate, to: hazard.coordinate)
                let radians = heading * .pi / 180
                let along = offset.east * sin(radians) + offset.north * cos(radians)
                let across = abs(offset.east * cos(radians) - offset.north * sin(radians))
                guard across <= 25 else { continue }
                if let direction = hazard.heading, Geo.angleDifference(direction, heading) > 60 { continue }
                alongDistance = along
            } else {
                for leg in path {
                    if let roadID = hazard.roadID, roadID != leg.roadID { continue }
                    let bearing = Geo.bearing(leg.start, leg.end)
                    if let direction = hazard.heading, Geo.angleDifference(direction, bearing) > 60 { continue }
                    let projection = Geo.project(hazard.coordinate, onto: leg.start, leg.end)
                    guard projection.distance <= 25 else { continue }
                    let offset = Geo.offset(from: leg.start, to: hazard.coordinate)
                    let radians = bearing * .pi / 180
                    let along = offset.east * sin(radians) + offset.north * cos(radians)
                    let length = leg.start.distance(to: leg.end)
                    guard along >= -2, along <= length + 2 else { continue }
                    let distance = leg.distanceBefore + projection.fraction * length
                    alongDistance = min(alongDistance ?? .greatestFiniteMagnitude, distance)
                }
            }
            if let distance = alongDistance, (8...radius).contains(distance) {
                result.append(UpcomingHazard(hazard: hazard, distance: distance))
            }
        }
        return result.sorted { $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance }
    }
}
