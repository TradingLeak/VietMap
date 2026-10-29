import Foundation

public enum Geo {
    public static let earthRadius = 6_371_000.0
    private static let radians = Double.pi / 180

    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = (b.latitude - a.latitude) * radians
        let dLon = (b.longitude - a.longitude) * radians
        let h = pow(sin(dLat / 2), 2) + cos(a.latitude * radians) * cos(b.latitude * radians) * pow(sin(dLon / 2), 2)
        return 2 * earthRadius * asin(sqrt(min(1, max(0, h))))
    }

    public static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * radians
        let lat2 = b.latitude * radians
        let lon = (b.longitude - a.longitude) * radians
        let y = sin(lon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon)
        return (atan2(y, x) / radians + 360).truncatingRemainder(dividingBy: 360)
    }

    public static func interpolate(_ a: Coordinate, _ b: Coordinate, fraction: Double) -> Coordinate {
        let t = min(1, max(0, fraction))
        return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    public struct Projection: Equatable, Sendable {
        public let coordinate: Coordinate
        public let fraction: Double
        public let distance: Double
    }

    public static func project(_ point: Coordinate, onto start: Coordinate, _ end: Coordinate) -> Projection {
        let scale = max(0.01, cos(start.latitude * radians))
        let x = (end.longitude - start.longitude) * scale
        let y = end.latitude - start.latitude
        let px = (point.longitude - start.longitude) * scale
        let py = point.latitude - start.latitude
        let length2 = x * x + y * y
        let t = length2 > 0 ? min(1, max(0, (px * x + py * y) / length2)) : 0
        let coordinate = interpolate(start, end, fraction: t)
        return Projection(coordinate: coordinate, fraction: t, distance: point.distance(to: coordinate))
    }

    public static func offset(from origin: Coordinate, to point: Coordinate) -> (east: Double, north: Double) {
        let north = (point.latitude - origin.latitude) * radians * earthRadius
        let east = (point.longitude - origin.longitude) * radians * earthRadius * cos(origin.latitude * radians)
        return (east, north)
    }
}

/// Bounded local grid. Building an index is done off the UI thread by the app.
struct SpatialGrid: Sendable {
    struct Cell: Hashable, Sendable { let x: Int; let y: Int }
    private let cellSize = 0.01
    private var roads: [Cell: [Int]] = [:]
    private var hazards: [Cell: [Int]] = [:]

    init(dataset: TrafficDataset) {
        for (index, road) in dataset.roads.enumerated() {
            let first = cell(road.start)
            let last = cell(road.end)
            for x in min(first.x, last.x)...max(first.x, last.x) {
                for y in min(first.y, last.y)...max(first.y, last.y) {
                    roads[Cell(x: x, y: y), default: []].append(index)
                }
            }
        }
        for (index, hazard) in dataset.hazards.enumerated() {
            hazards[cell(hazard.coordinate), default: []].append(index)
        }
    }

    func nearbyRoads(_ point: Coordinate, radius: Double) -> [Int] {
        indices(in: roads, near: point, radius: radius)
    }

    func nearbyHazards(_ point: Coordinate, radius: Double) -> [Int] {
        indices(in: hazards, near: point, radius: radius)
    }

    private func cell(_ point: Coordinate) -> Cell {
        Cell(x: Int(floor(point.longitude / cellSize)), y: Int(floor(point.latitude / cellSize)))
    }

    private func indices(in table: [Cell: [Int]], near point: Coordinate, radius: Double) -> [Int] {
        guard point.isValid, radius.isFinite, radius >= 0 else { return [] }
        let latitudeDelta = min(radius, 2_000) / 111_000
        let longitudeDelta = latitudeDelta / max(0.08, cos(point.latitude * .pi / 180))
        let lower = cell(Coordinate(latitude: point.latitude - latitudeDelta, longitude: point.longitude - longitudeDelta))
        let upper = cell(Coordinate(latitude: point.latitude + latitudeDelta, longitude: point.longitude + longitudeDelta))
        var result = Set<Int>()
        for x in lower.x...upper.x {
            for y in lower.y...upper.y {
                if let values = table[Cell(x: x, y: y)] { result.formUnion(values) }
            }
        }
        return result.sorted()
    }
}
