import Foundation

public struct RouteInstruction: Equatable, Sendable {
    public let text: String
    public let distanceAlongRoute: Double
    public init(text: String, distanceAlongRoute: Double) { self.text = text; self.distanceAlongRoute = distanceAlongRoute }
}

public struct RouteProgress: Equatable, Sendable {
    public var remainingMetres: Double
    public var distanceToInstruction: Double?
    public var nextInstruction: String?
    public var isOffRoute: Bool
    public var hasArrived: Bool
}

/// Route progress cannot jump backwards or across a loop just because another leg is nearby.
public struct RouteTracker: Sendable {
    public let coordinates: [Coordinate]
    public let instructions: [RouteInstruction]
    private let cumulative: [Double]
    public private(set) var travelledMetres: Double = 0
    private var lastTime: Date?
    private var offRouteSince: Date?
    private var announcedSteps = Set<Int>()
    private var arrivalAnnounced = false

    public init(coordinates: [Coordinate], instructions: [RouteInstruction]) {
        self.coordinates = coordinates
        self.instructions = instructions.sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
        var distances = [0.0]
        for index in coordinates.indices.dropFirst() {
            distances.append(distances.last! + coordinates[index - 1].distance(to: coordinates[index]))
        }
        self.cumulative = distances
    }

    public var totalMetres: Double { cumulative.last ?? 0 }

    public func distanceAlongRoute(to point: Coordinate) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        var nearest = Double.greatestFiniteMagnitude
        var along = 0.0
        for i in 1..<coordinates.count {
            let projection = Geo.project(point, onto: coordinates[i - 1], coordinates[i])
            if projection.distance < nearest {
                nearest = projection.distance
                along = cumulative[i - 1] + projection.fraction * (cumulative[i] - cumulative[i - 1])
            }
        }
        return along
    }

    public mutating func update(_ fix: LocationFix, now: Date) -> (RouteProgress?, Announcement?) {
        guard fix.isUsable(at: now), coordinates.count >= 2 else { return (nil, nil) }
        if let lastTime, fix.timestamp <= lastTime { return (nil, nil) }
        let delta = lastTime.map { max(1, fix.timestamp.timeIntervalSince($0)) } ?? 1
        // A long location outage is not permission to snap to an arbitrary future loop.
        let forwardWindow = min(1_000, max(180, (fix.speedMPS ?? 25) * min(delta, 15) + 100))
        var nearest = Double.greatestFiniteMagnitude
        var along = travelledMetres
        for i in 1..<coordinates.count {
            guard cumulative[i] >= travelledMetres - 40,
                  cumulative[i - 1] <= travelledMetres + forwardWindow else { continue }
            let projection = Geo.project(fix.coordinate, onto: coordinates[i - 1], coordinates[i])
            let position = cumulative[i - 1] + projection.fraction * (cumulative[i] - cumulative[i - 1])
            guard position >= travelledMetres - 40, position <= travelledMetres + forwardWindow else { continue }
            if projection.distance < nearest {
                nearest = projection.distance
                along = position
            }
        }
        lastTime = fix.timestamp
        let away = nearest > max(55, fix.horizontalAccuracy * 1.5)
        if away {
            if offRouteSince == nil { offRouteSince = fix.timestamp }
        } else {
            offRouteSince = nil
            travelledMetres = max(travelledMetres, along)
        }
        let offRoute = offRouteSince.map { fix.timestamp.timeIntervalSince($0) >= 8 } ?? false
        let remaining = max(0, totalMetres - travelledMetres)
        let arrived = !away && remaining <= 35 && fix.coordinate.distance(to: coordinates.last!) <= 50
        let next = instructions.enumerated().first { $0.element.distanceAlongRoute >= travelledMetres + 8 }
        let distance = next.map { max(0, $0.element.distanceAlongRoute - travelledMetres) }
        var announcement: Announcement?
        if !away, let next, let distance, distance <= max(100, (fix.validSpeedKmh ?? 0) / 3.6 * 10), announcedSteps.insert(next.offset).inserted {
            announcement = Announcement(text: "Còn \(max(10, Int(distance / 10) * 10)) mét, \(next.element.text)", priority: 2)
        }
        if arrived && !arrivalAnnounced {
            arrivalAnnounced = true
            announcement = Announcement(text: "Bạn đã đến gần điểm đến. Hãy dừng xe an toàn.", priority: 2)
        }
        return (RouteProgress(remainingMetres: remaining, distanceToInstruction: distance, nextInstruction: next?.element.text, isOffRoute: offRoute, hasArrived: arrived), announcement)
    }
}
