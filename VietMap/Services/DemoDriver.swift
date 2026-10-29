import Foundation
import VietMapCore

struct DemoDriver {
    private let roads: [RoadSegment]
    private var index = 0
    private var distance = 40.0
    private var elapsed = 0.0

    init(dataset: TrafficDataset) { roads = dataset.roads }

    mutating func next(at date: Date, delta: Double) -> LocationFix? {
        guard !roads.isEmpty else { return nil }
        let step = min(3, max(0.1, delta))
        elapsed += step
        let speed = max(20, 61 + 12 * sin(elapsed / 13))
        distance += speed / 3.6 * step
        var road = roads[index]
        var length = road.start.distance(to: road.end)
        while distance > length {
            distance -= length
            index = (index + 1) % roads.count
            road = roads[index]
            length = road.start.distance(to: road.end)
        }
        return LocationFix(coordinate: Geo.interpolate(road.start, road.end, fraction: distance / length), speedMPS: speed / 3.6,
                           heading: Geo.bearing(road.start, road.end), horizontalAccuracy: 3, timestamp: date)
    }
}
