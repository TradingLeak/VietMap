import Foundation
import CoreLocation

/// Chiếu lên từng đoạn trong hệ tọa độ cục bộ; không phải map-matching theo mạng đường.
struct RouteGeometry {
    struct Match {
        let coordinate: CLLocationCoordinate2D
        let segmentIndex: Int
        let distance: Double
        let along: Double
    }
    private struct Segment {
        let start: CLLocationCoordinate2D, end: CLLocationCoordinate2D
        let index: Int, startDistance: Double, length: Double
    }
    private let segments: [Segment]
    let length: Double

    init?(_ coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2, coordinates.allSatisfy({
            $0.latitude.isFinite && $0.longitude.isFinite && CLLocationCoordinate2DIsValid($0)
        }) else { return nil }
        var segments: [Segment] = []
        var total = 0.0
        for i in 0..<(coordinates.count - 1) {
            let a = coordinates[i], b = coordinates[i + 1]
            let distance = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if distance > 0 && distance.isFinite {
                segments.append(Segment(start: a, end: b, index: i, startDistance: total, length: distance))
                total += distance
            }
        }
        guard total > 0, total.isFinite else { return nil }
        self.segments = segments; length = total
    }

    func closest(to point: CLLocationCoordinate2D, preferredAlong: Double? = nil, minimumAlong: Double = 0) -> Match? {
        guard point.latitude.isFinite, point.longitude.isFinite, CLLocationCoordinate2DIsValid(point) else { return nil }
        let scale = 6_371_000.0 * Double.pi / 180
        let cosLat = max(1e-9, abs(cos(point.latitude * .pi / 180)))
        var best: Match?
        for segment in segments {
            let x = Self.wrap(segment.start.longitude - point.longitude) * scale * cosLat
            let y = (segment.start.latitude - point.latitude) * scale
            let dx = Self.wrap(segment.end.longitude - segment.start.longitude) * scale * cosLat
            let dy = (segment.end.latitude - segment.start.latitude) * scale
            let length2 = dx * dx + dy * dy
            guard length2 > 0 else { continue }
            let t = min(1, max(0, -(x * dx + y * dy) / length2))
            let along = segment.startDistance + t * segment.length
            guard along + 0.01 >= minimumAlong else { continue }
            let lat = segment.start.latitude + t * (segment.end.latitude - segment.start.latitude)
            let lon = Self.wrap(segment.start.longitude + t * Self.wrap(segment.end.longitude - segment.start.longitude))
            let snapped = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let distance = CLLocation(latitude: point.latitude, longitude: point.longitude).distance(from: CLLocation(latitude: lat, longitude: lon))
            let match = Match(coordinate: snapped, segmentIndex: segment.index, distance: distance, along: along)
            if let old = best {
                // Chỉ ưu tiên continuity khi khoảng cách gần tương đương, giảm nhảy tại giao cắt.
                if distance < old.distance - 1 || (abs(distance - old.distance) <= 1 &&
                    abs(along - (preferredAlong ?? minimumAlong)) < abs(old.along - (preferredAlong ?? minimumAlong))) { best = match }
            } else { best = match }
        }
        return best
    }
    private static func wrap(_ longitude: Double) -> Double {
        var result = longitude.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }; if result < -180 { result += 360 }
        return result
    }
}
