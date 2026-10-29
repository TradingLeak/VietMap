import Foundation
import CoreLocation
import Combine

/// Engine thử nghiệm. ObservableObject/Combine giữ tương thích iOS 16.
@MainActor
public final class NavigationEngine: ObservableObject {
    @Published public private(set) var currentRoute: Route?
    @Published public private(set) var currentStepIndex = 0
    @Published public private(set) var distanceToNextManeuver: Double = 0
    @Published public private(set) var distanceRemaining: Double = 0
    @Published public private(set) var durationRemaining: TimeInterval = 0
    @Published public private(set) var estimatedArrivalTime: Date?
    @Published public private(set) var isOffRoute = false
    @Published public private(set) var progressFraction: Double = 0
    @Published public private(set) var isNavigating = false
    @Published public private(set) var isRerouting = false
    @Published public private(set) var isArrived = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var snappedLocation: CLLocation?

    public var currentStep: RouteStep? {
        guard let route = currentRoute, route.steps.indices.contains(currentStepIndex) else { return nil }
        return route.steps[currentStepIndex]
    }

    private let service: RoutingServiceProtocol
    private let locationManager: LocationManager?
    private let announcer: NavigationAnnouncing
    private var subscriptions = Set<AnyCancellable>()
    private var geometry: RouteGeometry?
    private var stepPositions: [Double] = []
    private var waypointPositions: [Double] = []
    private var traveledGeometry: Double = 0
    private var lastLocation: CLLocation?
    private var lastTimestamp: Date?
    private var offRouteCount = 0
    private var firstOffRouteTimestamp: Date?
    private var lastOffRouteTimestamp: Date?
    private var announced: Set<Int> = []
    private var rerouteTask: Task<Void, Never>?
    private var generation = UUID()
    private let background = BackgroundTaskManager()
    private var lastRerouteAttempt: Date?

    /// Có thể truyền nil cho locationManager để cấp GPS thủ công hoặc kiểm thử.
    public convenience init() {
        self.init(service: OSRMRoutingService(), locationManager: .shared, announcer: SpeechNavigationAnnouncer.shared)
    }

    public init(service: RoutingServiceProtocol, locationManager: LocationManager?, announcer: NavigationAnnouncing) {
        self.service = service; self.locationManager = locationManager; self.announcer = announcer
        locationManager?.$currentLocation.sink { [weak self] location in
            guard let location, self?.isNavigating == true else { return }
            self?.updateProgress(with: location)
        }.store(in: &subscriptions)
        locationManager?.$authorizationStatus.sink { [weak self] status in
            guard let self, self.isNavigating, status == .denied || status == .restricted else { return }
            self.stopNavigation()
            self.lastError = "Không thể dẫn đường vì quyền vị trí bị từ chối hoặc hạn chế."
        }.store(in: &subscriptions)
    }

    public func startNavigation(route: Route) {
        stopNavigation()
        guard install(route) else { lastError = "Tuyến đường không hợp lệ hoặc không có hình học."; return }
        isNavigating = true
        locationManager?.startNavigation()
        if let manager = locationManager, !manager.isNavigating {
            stopNavigation()
            lastError = "Không thể bắt đầu dẫn đường: hãy kiểm tra quyền vị trí."
            return
        }
        if locationManager != nil { background.start(engine: self); NavigationEvents.record(.navigationStart) }
        if let location = locationManager?.currentLocation { updateProgress(with: location) }
    }

    public func stopNavigation() {
        background.stop()
        generation = UUID()
        rerouteTask?.cancel(); rerouteTask = nil
        locationManager?.stopNavigation()
        announcer.stop()
        isNavigating = false; isRerouting = false; isArrived = false; isOffRoute = false
        currentRoute = nil; geometry = nil; stepPositions = []; waypointPositions = []
        currentStepIndex = 0; distanceToNextManeuver = 0; distanceRemaining = 0
        durationRemaining = 0; estimatedArrivalTime = nil; progressFraction = 0; snappedLocation = nil
        traveledGeometry = 0; lastLocation = nil; lastTimestamp = nil; lastRerouteAttempt = nil
        resetOffRoute(); announced.removeAll(); lastError = nil
    }

    /// Nil nếu route/điểm không hợp lệ; không làm thay đổi trạng thái dẫn đường.
    public func snapToRoute(location: CLLocation) -> (snappedLocation: CLLocation, segmentIndex: Int, distanceFromRoute: Double)? {
        guard let match = geometry?.closest(to: location.coordinate, preferredAlong: traveledGeometry) else { return nil }
        let snapped = CLLocation(coordinate: match.coordinate, altitude: location.altitude,
                                 horizontalAccuracy: location.horizontalAccuracy, verticalAccuracy: location.verticalAccuracy,
                                 course: location.course, speed: location.speed, timestamp: location.timestamp)
        return (snapped, match.segmentIndex, match.distance)
    }

    public func updateProgress(with location: CLLocation) {
        guard isNavigating, let route = currentRoute, let geometry,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy.isFinite,
              location.timestamp.timeIntervalSinceNow > -30, location.timestamp.timeIntervalSinceNow < 10,
              lastTimestamp.map({ location.timestamp > $0 }) ?? true,
              let match = geometry.closest(to: location.coordinate, preferredAlong: traveledGeometry) else { return }
        lastTimestamp = location.timestamp
        lastLocation = location
        // GPS sai số lớn không đủ tin cậy để cập nhật tiến độ hay kết luận lệch tuyến.
        guard location.horizontalAccuracy <= 50 else { isOffRoute = false; resetOffRoute(); return }
        let wasOffRoute = isOffRoute
        isOffRoute = match.distance > 50
        // Khi quay lại tuyến cũ, không áp dụng kết quả reroute đang chạy.
        if wasOffRoute && !isOffRoute && isRerouting {
            generation = UUID(); rerouteTask?.cancel(); rerouteTask = nil
            isRerouting = false; lastError = nil
        }
        if isOffRoute {
            recordOffRoute(at: location.timestamp)
            return
        }
        resetOffRoute()
        snappedLocation = CLLocation(coordinate: match.coordinate, altitude: location.altitude,
                                     horizontalAccuracy: location.horizontalAccuracy, verticalAccuracy: location.verticalAccuracy,
                                     course: location.course, speed: location.speed, timestamp: location.timestamp)
        // Chống GPS nhảy lùi; khi tính tuyến mới, tiến độ được reset về 0.
        traveledGeometry = max(traveledGeometry, min(geometry.length, match.along))
        progressFraction = min(1, max(0, traveledGeometry / geometry.length))
        distanceRemaining = max(0, route.distance * (1 - progressFraction))
        // ETA tỷ lệ theo thời gian dự kiến ban đầu; không chia cho tốc độ GPS nhiễu/gần 0.
        durationRemaining = max(0, route.duration * (1 - progressFraction))
        estimatedArrivalTime = Date().addingTimeInterval(durationRemaining)
        advanceSteps(route: route, geometry: geometry)
        if isDestinationReached(route: route, location: location) {
            isArrived = true; isNavigating = false; isOffRoute = false
            progressFraction = 1; distanceRemaining = 0; durationRemaining = 0; distanceToNextManeuver = 0
            estimatedArrivalTime = Date(); locationManager?.stopNavigation()
            rerouteTask?.cancel(); rerouteTask = nil; generation = UUID(); isRerouting = false
            announcer.announce("Đã đến nơi")
            if locationManager != nil { background.arrived() }
        } else {
            announceIfNeeded()
            if locationManager != nil { background.update(engine: self) }
        }
    }

    private func install(_ route: Route) -> Bool {
        guard route.distance.isFinite, route.distance > 0, route.duration.isFinite, route.duration >= 0,
              let shape = RouteGeometry(route.geometry), route.steps.allSatisfy({ CLLocationCoordinate2DIsValid($0.coordinate) }) else { return false }
        geometry = shape
        currentRoute = route
        traveledGeometry = 0; progressFraction = 0; snappedLocation = nil
        distanceRemaining = route.distance; durationRemaining = route.duration
        estimatedArrivalTime = Date().addingTimeInterval(route.duration)
        currentStepIndex = route.steps.count > 1 && route.steps[0].maneuver == .depart ? 1 : 0
        var previous = 0.0
        stepPositions = route.steps.map { step in
            let along = shape.closest(to: step.coordinate, preferredAlong: previous, minimumAlong: max(0, previous - 1))?.along ?? previous
            previous = max(previous, along); return previous
        }
        previous = 0
        waypointPositions = route.waypoints.map { point in
            let along = shape.closest(to: point, preferredAlong: previous, minimumAlong: max(0, previous - 1))?.along ?? previous
            previous = max(previous, along); return previous
        }
        distanceToNextManeuver = stepPositions.indices.contains(currentStepIndex) ? stepPositions[currentStepIndex] / shape.length * route.distance : 0
        lastLocation = nil; lastTimestamp = nil; announced.removeAll(); resetOffRoute()
        isOffRoute = false; isArrived = false; lastError = nil
        return true
    }

    private func advanceSteps(route: Route, geometry: RouteGeometry) {
        guard !route.steps.isEmpty else { distanceToNextManeuver = distanceRemaining; return }
        while currentStepIndex < route.steps.count - 1 && stepPositions[currentStepIndex] - traveledGeometry <= 20 {
            currentStepIndex += 1
            announced.removeAll()
        }
        let meters = max(0, stepPositions[currentStepIndex] - traveledGeometry)
        distanceToNextManeuver = meters / geometry.length * route.distance
    }

    private func isDestinationReached(route: Route, location: CLLocation) -> Bool {
        guard distanceRemaining <= 20, let end = route.geometry.last else { return false }
        return location.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) <= 20
    }

    private func announceIfNeeded() {
        guard let step = currentStep, step.maneuver != .depart else { return }
        let thresholds = [50, 200, 500, 1000]
        guard let threshold = thresholds.first(where: { distanceToNextManeuver <= Double($0) && !announced.contains($0) }) else { return }
        // Nếu GPS nhảy qua nhiều ngưỡng, chỉ phát thông báo gần nhất, không phát dồn.
        thresholds.filter { $0 >= threshold }.forEach { announced.insert($0) }
        let phrase = step.instruction
        let text: String
        if step.maneuver == .arrive {
            let target = currentStepIndex == (currentRoute?.steps.count ?? 0) - 1 ? "điểm đến" : "điểm dừng"
            switch threshold {
            case 1000: text = "Còn 1 ki-lô-mét đến \(target)"
            case 500: text = "Còn 500 mét đến \(target)"
            case 200: text = "Chuẩn bị đến \(target)"
            default: text = "Sắp đến \(target)"
            }
            announcer.announce(text)
            return
        }
        switch threshold {
        case 1000: text = "Sau 1 ki-lô-mét: \(phrase)"
        case 500: text = "Sau 500 mét: \(phrase)"
        case 200: text = "Chuẩn bị: \(phrase)"
        default: text = "Ngay bây giờ: \(phrase)"
        }
        announcer.announce(text)
    }

    private func resetOffRoute() { offRouteCount = 0; firstOffRouteTimestamp = nil; lastOffRouteTimestamp = nil }
    private func recordOffRoute(at timestamp: Date) {
        if let last = lastOffRouteTimestamp, timestamp.timeIntervalSince(last) > 5 { resetOffRoute() }
        guard lastOffRouteTimestamp.map({ timestamp.timeIntervalSince($0) >= 1 }) ?? true else { return }
        if offRouteCount == 0 { firstOffRouteTimestamp = timestamp }
        offRouteCount += 1; lastOffRouteTimestamp = timestamp
        guard offRouteCount >= 3, let first = firstOffRouteTimestamp, timestamp.timeIntervalSince(first) >= 2,
              !isRerouting, lastRerouteAttempt.map({ Date().timeIntervalSince($0) >= 15 }) ?? true else { return }
        rerouteTask?.cancel()
        rerouteTask = Task { [weak self] in
            guard let self else { return }
            await self.recalculateRoute()
        }
    }

    public func recalculateRoute() async {
        guard isNavigating, !isRerouting, let oldRoute = currentRoute, let location = lastLocation,
              let destination = oldRoute.destination ?? oldRoute.geometry.last,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              location.timestamp.timeIntervalSinceNow > -30 else { return }
        let id = generation
        isRerouting = true; lastError = nil; lastRerouteAttempt = Date()
        defer { if generation == id { isRerouting = false } }
        let pending = zip(oldRoute.waypoints, waypointPositions).filter { $0.1 > traveledGeometry + 20 }.map(\.0)
        do {
            let route = try await service.calculateRoute(from: location.coordinate, to: destination, waypoints: pending, profile: oldRoute.profile)
            guard !Task.isCancelled, generation == id, isNavigating else { return }
            let latestLocation = lastLocation ?? location
            guard install(route) else { throw RoutingError.invalidResponse }
            NavigationEvents.record(.routeRecalculated)
            isRerouting = false
            updateProgress(with: latestLocation)
        } catch {
            guard !Task.isCancelled, generation == id, isNavigating else { return }
            isRerouting = false; lastError = "Không thể tính lại tuyến: \(error.localizedDescription)"
            // Giữ tuyến cũ, đợi cooldown rồi thử lại nếu vẫn lệch.
        }
    }
}
