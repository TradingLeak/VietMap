#if targetEnvironment(simulator)
import Foundation
import CoreLocation

/// GPX không tự điều khiển Core Location: phát các điểm đã đóng gói qua cùng pipeline.
@MainActor
final class GPXLocationSimulator: NSObject, XMLParserDelegate {
    private var points: [CLLocationCoordinate2D] = []
    private var index = 0
    private var timer: Timer?
    private let emit: (CLLocation) -> Void
    private let interval: TimeInterval = 2

    init(emit: @escaping (CLLocation) -> Void) {
        self.emit = emit
        super.init()
    }

    @discardableResult
    func start() -> Bool {
        if timer != nil { return true }
        if points.isEmpty {
            guard let url = Bundle.module.url(forResource: "simulated_route_hanoi", withExtension: "gpx"),
                  let parser = XMLParser(contentsOf: url) else { return false }
            parser.delegate = self
            guard parser.parse(), points.count >= 2 else { points.removeAll(); return false }
        }
        emitNext()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.emitNext() }
        }
        return true
    }

    func stop() { timer?.invalidate(); timer = nil }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        guard elementName == "trkpt", let lat = attributes["lat"].flatMap(Double.init),
              let lon = attributes["lon"].flatMap(Double.init) else { return }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        if CLLocationCoordinate2DIsValid(coordinate) { points.append(coordinate) }
    }

    private func emitNext() {
        let point = points[index]
        let next = points[(index + 1) % points.count]
        let previous = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let destination = CLLocation(latitude: next.latitude, longitude: next.longitude)
        // Không nối tốc độ giả giữa cuối và đầu tuyến khi lặp.
        let distance = index == points.count - 1 ? 0 : destination.distance(from: previous)
        let lat1 = point.latitude * .pi / 180, lat2 = next.latitude * .pi / 180
        let delta = (next.longitude - point.longitude) * .pi / 180
        let angle = atan2(sin(delta) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)) * 180 / .pi
        let direction = (angle + 360).truncatingRemainder(dividingBy: 360)
        emit(CLLocation(coordinate: point, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                        course: direction, speed: distance / interval, timestamp: Date()))
        index = (index + 1) % points.count
    }
}
#endif
