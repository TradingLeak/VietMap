import MapKit
import Combine
import VietMapCore

@MainActor
final class NavigationService: ObservableObject {
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var routes: [MKRoute] = []
    @Published private(set) var destination: MKMapItem?
    @Published private(set) var activeRoute: MKRoute?
    @Published private(set) var progress: RouteProgress?
    @Published private(set) var isSearching = false
    @Published private(set) var isCalculating = false
    @Published var errorMessage: String?
    private var tracker: RouteTracker?
    private var searchRequest: MKLocalSearch?
    private var directionRequest: MKDirections?
    private var searchToken = UUID()
    private var directionToken = UUID()
    private var lastReroute: Date?

    func search(_ text: String, around coordinate: Coordinate?) async {
        searchRequest?.cancel()
        let token = UUID(); searchToken = token
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { results = []; isSearching = false; return }
        isSearching = true; errorMessage = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let coordinate { request.region = MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000) }
        let search = MKLocalSearch(request: request); searchRequest = search
        defer { if searchToken == token { isSearching = false } }
        do {
            let response = try await search.start()
            guard token == searchToken, !Task.isCancelled else { return }
            results = Array(response.mapItems.prefix(12))
            if results.isEmpty { errorMessage = "Không tìm thấy địa điểm. Hãy thử tên hoặc địa chỉ cụ thể hơn." }
        } catch {
            guard token == searchToken, !Task.isCancelled else { return }
            results = []
            errorMessage = "Không tìm kiếm được. Kiểm tra kết nối mạng; Apple Maps có thể chưa phủ đủ khu vực này."
        }
    }

    func calculate(to item: MKMapItem, from coordinate: Coordinate, rerouting: Bool = false) async {
        directionRequest?.cancel()
        let token = UUID(); directionToken = token
        isCalculating = true; errorMessage = nil
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
        request.destination = item
        request.transportType = .automobile
        request.requestsAlternateRoutes = !rerouting
        let directions = MKDirections(request: request); directionRequest = directions
        defer { if token == directionToken { isCalculating = false } }
        do {
            let response = try await directions.calculate()
            guard token == directionToken, !Task.isCancelled else { return }
            guard !response.routes.isEmpty else {
                errorMessage = "Apple Maps chưa cung cấp tuyến ô tô cho khu vực này. Không có tuyến giả được tạo thay thế."
                return
            }
            destination = item
            routes = response.routes
            results = []
            if rerouting, let route = routes.first { start(route) }
        } catch {
            guard token == directionToken, !Task.isCancelled else { return }
            errorMessage = "Không tính được tuyến ô tô. Cần mạng và vùng hỗ trợ chỉ đường của Apple Maps."
        }
    }

    func start(_ route: MKRoute) {
        let coordinates = route.polyline.vietCoordinates
        guard coordinates.count >= 2 else { errorMessage = "Tuyến đường không có hình học hợp lệ."; return }
        let geometry = RouteTracker(coordinates: coordinates, instructions: [])
        let instructions = route.steps.compactMap { step -> RouteInstruction? in
            guard !step.instructions.isEmpty, let start = step.polyline.vietCoordinates.first else { return nil }
            return RouteInstruction(text: step.instructions, distanceAlongRoute: geometry.distanceAlongRoute(to: start))
        }
        tracker = RouteTracker(coordinates: coordinates, instructions: instructions)
        activeRoute = route
        progress = nil
    }

    func update(_ fix: LocationFix, now: Date) -> Announcement? {
        guard tracker != nil else { return nil }
        let (value, announcement) = tracker?.update(fix, now: now) ?? (nil, nil)
        if let value { progress = value }
        if value?.isOffRoute == true, !isCalculating, let destination,
           lastReroute.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            lastReroute = now
            Task { await calculate(to: destination, from: fix.coordinate, rerouting: true) }
        }
        return announcement
    }

    func invalidateProgress() { progress = nil }

    func stop() {
        searchToken = UUID(); directionToken = UUID()
        searchRequest?.cancel(); directionRequest?.cancel()
        isCalculating = false; isSearching = false
        activeRoute = nil; tracker = nil; progress = nil
        lastReroute = nil
    }

    func clearPreview() { routes = []; destination = nil; errorMessage = nil }
}

extension MKPolyline {
    var vietCoordinates: [Coordinate] {
        var values = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&values, range: NSRange(location: 0, length: pointCount))
        return values.map(Coordinate.init)
    }
}
