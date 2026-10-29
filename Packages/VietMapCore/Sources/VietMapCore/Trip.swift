import Foundation

public struct TripPoint: Codable, Equatable, Sendable {
    public var coordinate: Coordinate
    public var timestamp: Date
    public var speedKmh: Double?
    public var speedLimit: Int?
}

public struct Trip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var isDemo: Bool
    public var wasInterrupted: Bool
    public var distanceMetres: Double
    public var maximumSpeedKmh: Double
    public var points: [TripPoint]

    public init(id: UUID = UUID(), startedAt: Date = Date(), isDemo: Bool = false) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.isDemo = isDemo
        self.wasInterrupted = false
        self.distanceMetres = 0
        self.maximumSpeedKmh = 0
        self.points = []
    }

    public var duration: TimeInterval { max(0, (endedAt ?? points.last?.timestamp ?? startedAt).timeIntervalSince(startedAt)) }
    public var averageSpeedKmh: Double { duration > 0 ? distanceMetres / duration * 3.6 : 0 }

    /// Samples at most once per 3 seconds; rejects impossible jumps and bridges no GPS gaps.
    public mutating func append(_ fix: LocationFix, speedLimit: Int?, now: Date) {
        guard endedAt == nil, fix.isUsable(at: now), points.count < 100_000 else { return }
        if let last = points.last {
            let delta = fix.timestamp.timeIntervalSince(last.timestamp)
            guard delta >= 3 else { return }
            let distance = last.coordinate.distance(to: fix.coordinate)
            // A GPS gap is retained in the log, but never counted as travelled distance.
            if delta <= 15 {
                guard distance / delta <= 85 else { return }
                if distance >= max(3, fix.horizontalAccuracy * 0.3), (fix.validSpeedKmh ?? 0) >= 3 {
                    distanceMetres += distance
                }
            }
        }
        if let speed = fix.validSpeedKmh { maximumSpeedKmh = max(maximumSpeedKmh, speed) }
        points.append(TripPoint(coordinate: fix.coordinate, timestamp: fix.timestamp, speedKmh: fix.validSpeedKmh, speedLimit: speedLimit))
    }

    public mutating func finish(at date: Date, interrupted: Bool = false) {
        endedAt = max(date, startedAt)
        wasInterrupted = interrupted
    }
}

public enum TripExport {
    public static func csv(_ trip: Trip) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = ["timestamp,latitude,longitude,speed_kmh,speed_limit_kmh,is_demo"]
        for point in trip.points {
            let speed = point.speedKmh.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
            rows.append("\(formatter.string(from: point.timestamp)),\(point.coordinate.latitude),\(point.coordinate.longitude),\(speed),\(point.speedLimit.map(String.init) ?? ""),\(trip.isDemo)")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func gpx(_ trip: Trip) -> String {
        let formatter = ISO8601DateFormatter()
        var result = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"VietMap\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>VietMap \(trip.isDemo ? "demo " : "")\(trip.id.uuidString)</name>"
        var previous: Date?
        for point in trip.points {
            // A separate GPX segment prevents drawing a fictional line across GPS loss.
            if previous == nil || point.timestamp.timeIntervalSince(previous!) > 15 {
                if previous != nil { result += "</trkseg>" }
                result += "<trkseg>"
            }
            result += "<trkpt lat=\"\(point.coordinate.latitude)\" lon=\"\(point.coordinate.longitude)\"><time>\(formatter.string(from: point.timestamp))</time></trkpt>"
            previous = point.timestamp
        }
        if previous != nil { result += "</trkseg>" }
        result += "</trk></gpx>\n"
        return result
    }
}
