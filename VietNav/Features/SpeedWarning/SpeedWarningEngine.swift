import Foundation
import CoreLocation
import Combine

public struct WarningItem: Identifiable {
    public let id: Int64
    public let node: TrafficNode
    public let distance: Double
    /// Góc phương vị từ xe đến điểm, tính theo hướng bắc thực.
    public let bearing: Double
    public let hasAnnounced: Bool
}

public struct TrafficWarningSnapshot {
    public let nodes: [TrafficNode]
    public let speedLimit: Int?
    public init(nodes: [TrafficNode], speedLimit: Int?) { self.nodes = nodes; self.speedLimit = speedLimit }
}

/// Data source bất đồng bộ để không truy vấn SQLite trên main thread và có thể mock.
public protocol TrafficWarningDataSource {
    func load(latitude: Double, longitude: Double, heading: Double) async throws -> TrafficWarningSnapshot
}

public struct SQLiteTrafficWarningDataSource: TrafficWarningDataSource {
    private let database: TrafficDatabase
    public init(database: TrafficDatabase = .shared) { self.database = database }
    public func load(latitude: Double, longitude: Double, heading: Double) async throws -> TrafficWarningSnapshot {
        let database = self.database
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            // findNearestNodes dùng R-Tree, xử lý kinh tuyến 180° và lọc khoảng cách thực.
            let nodes = try database.findNearestNodes(latitude: latitude, longitude: longitude, radiusMeters: 2000, limit: Int.max)
            let limit = try database.findSpeedLimitAt(latitude: latitude, longitude: longitude, bearing: heading)
            return TrafficWarningSnapshot(nodes: nodes, speedLimit: limit)
        }.value
    }
}

@MainActor
public protocol SpeedWarningAnnouncing {
    /// Chỉ đánh dấu đã nhận khi audio đã nhận; suppressed không chặn các loại khác.
    func announce(_ message: String, category: AlertCategory, priority: AlertPriority) -> AlertDeliveryResult
}

@MainActor
public final class SpeechSpeedWarningAnnouncer: SpeedWarningAnnouncing {
    private let audio: AudioAlertManager
    public init(audio: AudioAlertManager) { self.audio = audio }
    public func announce(_ message: String, category: AlertCategory, priority: AlertPriority) -> AlertDeliveryResult {
        // Không xếp hàng cảnh báo GPS có thể hết hạn trước khi được đọc.
        audio.submit(AlertRequest(priority: priority, text: message, sound: .beep, category: category, maxAge: 8), onlyIfIdle: true)
    }
}

private struct WarningCandidate {
    let node: TrafficNode
    let id: Int64
    let distance: Double
    let bearing: Double
}

/// Hàm thuần chạy ngoài main thread; khoảng cách được tính bằng Core Location.
private enum WarningGeometry {
    static func distance(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude).distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
    static func bearing(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let delta = (to.longitude - from.longitude) * .pi / 180
        let y = sin(delta) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    static func difference(_ a: Double, _ b: Double) -> Double {
        guard a.isFinite, b.isFinite else { return .infinity }
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }
    static func candidates(nodes: [TrafficNode], coordinate: CLLocationCoordinate2D, heading: Double, radius: Double) -> [WarningCandidate] {
        guard heading.isFinite, heading >= 0, heading <= 360, CLLocationCoordinate2DIsValid(coordinate) else { return [] }
        return nodes.compactMap { node in
            guard let id = node.id else { return nil }
            let point = CLLocationCoordinate2D(latitude: node.latitude, longitude: node.longitude)
            guard node.latitude.isFinite, node.longitude.isFinite, CLLocationCoordinate2DIsValid(point) else { return nil }
            let meters = distance(coordinate, point)
            guard meters >= 1, meters <= radius else { return nil }
            let direction = bearing(coordinate, point)
            guard difference(heading, direction) < 60 else { return nil }
            if let effective = node.bearing {
                guard effective.isFinite, effective >= 0, effective <= 360, difference(heading, effective) < 45 else { return nil }
            }
            return WarningCandidate(node: node, id: id, distance: meters, bearing: direction)
        }.sorted { $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance }
    }
}

/// Cảnh báo thử nghiệm: không suy đoán giới hạn pháp lý khi chưa xác định được đường.
/// ObservableObject thay cho @Observable để giữ hỗ trợ iOS 16.
@MainActor
public final class SpeedWarningEngine: ObservableObject {
    @Published public private(set) var currentSpeed: Double = 0
    @Published public private(set) var currentSpeedLimit: Int?
    @Published public private(set) var isOverSpeeding = false
    @Published public private(set) var overspeedingDuration: TimeInterval = 0
    @Published public private(set) var upcomingWarnings: [WarningItem] = []
    @Published public private(set) var closestWarning: WarningItem?
    @Published public private(set) var hasReliableHeading = false
    @Published public private(set) var hasFreshLocation = false
    @Published public private(set) var hasSpeedMeasurement = false
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public private(set) var lastError: String?
    @Published public private(set) var isActive = false
    @Published public var overspeedTolerance: Double = 5
    @Published public var warningDistance: Double = 500
    @Published public var alertDistance: Double = 300

    private struct Sample {
        let location: CLLocation
        let heading: Double?
        let speed: Double
        let hasValidSpeed: Bool
    }
    private let store: TrafficWarningDataSource
    private let locationManager: LocationManager?
    private let announcer: SpeedWarningAnnouncing
    private let now: () -> Date
    private var subscriptions = Set<AnyCancellable>()
    private var worker: Task<Void, Never>?
    private var pending: Sample?
    private var generation = UUID()
    private var lastAcceptedTimestamp: Date?
    private var freshnessTimer: Timer?
    private var overspeedStart: Date?
    private var lastOverspeedSample: Date?
    private var lastOverspeedAnnouncement: Date?
    private var overspeedLimit: Int?
    private var announced: [Int64: Date] = [:]
    private var finalAnnouncements: [Int64: Date] = [:]

    public convenience init() {
        self.init(store: SQLiteTrafficWarningDataSource(), locationManager: .shared,
                  announcer: SpeechSpeedWarningAnnouncer(audio: .shared))
    }
    /// locationManager=nil cho phép cung cấp GPS thủ công hoặc unit test.
    public init(store: TrafficWarningDataSource, locationManager: LocationManager?,
                announcer: SpeedWarningAnnouncing, now: @escaping () -> Date = Date.init) {
        self.store = store; self.locationManager = locationManager; self.announcer = announcer; self.now = now
        locationManager?.$currentLocation.sink { [weak self] location in
            guard let self, self.isActive, let location else { return }
            let speed = location.speed >= 0 && location.speed.isFinite ? location.speed * 3.6 : 0
            var heading: Double?
            if speed > 5, location.course.isFinite, location.course >= 0, location.course < 360 {
                heading = location.course
            } else if let compass = self.locationManager?.heading, compass.headingAccuracy >= 0,
                      compass.trueHeading.isFinite, compass.trueHeading >= 0, compass.trueHeading < 360 {
                heading = compass.trueHeading
            }
            self.enqueue(location: location, heading: heading)
        }.store(in: &subscriptions)
    }

    /// Không tự xin quyền vị trí; caller điều khiển lifecycle của LocationManager.
    public func start() {
        guard !isActive else { return }
        isActive = true
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFreshness() }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
        if let location = locationManager?.currentLocation {
            let speed = location.speed >= 0 && location.speed.isFinite ? location.speed * 3.6 : 0
            let course = speed > 5 && location.course >= 0 && location.course < 360 && location.course.isFinite ? location.course : nil
            let compass = locationManager?.heading
            let heading = course ?? ((compass?.headingAccuracy ?? -1) >= 0 && (compass?.trueHeading ?? -1) >= 0 && (compass?.trueHeading ?? 360) < 360 ? compass?.trueHeading : nil)
            enqueue(location: location, heading: heading)
        }
    }
    public func stop() {
        isActive = false; generation = UUID(); worker?.cancel(); worker = nil; pending = nil
        freshnessTimer?.invalidate(); freshnessTimer = nil
        lastAcceptedTimestamp = nil; lastUpdatedAt = nil; hasFreshLocation = false; hasSpeedMeasurement = false
        currentSpeed = 0; currentSpeedLimit = nil; hasReliableHeading = false
        resetOverspeed(); upcomingWarnings = []; closestWarning = nil; lastError = nil
    }

    deinit { freshnessTimer?.invalidate() }

    /// Cung cấp heading theo độ bắc thực; không gọi khi không biết hướng.
    public func process(location: CLLocation, heading: Double) { enqueue(location: location, heading: heading) }

    private func enqueue(location: CLLocation, heading: Double?) {
        guard isActive, location.coordinate.latitude.isFinite, location.coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50,
              location.timestamp.timeIntervalSince(now()) >= -30, location.timestamp.timeIntervalSince(now()) <= 5,
              lastAcceptedTimestamp.map({ location.timestamp > $0 }) ?? true else { return }
        lastAcceptedTimestamp = location.timestamp
        let validSpeed = location.speed.isFinite && location.speed >= 0 && (location.speed * 3.6).isFinite
        let speed = validSpeed ? location.speed * 3.6 : 0
        let direction = heading.flatMap { $0.isFinite && $0 >= 0 && $0 <= 360 ? $0.truncatingRemainder(dividingBy: 360) : nil }
        pending = Sample(location: location, heading: direction, speed: speed, hasValidSpeed: validSpeed)
        guard worker == nil else { return }
        let token = generation
        worker = Task { [weak self] in
            guard let self else { return }
            await self.drain(token: token)
        }
    }

    private func drain(token: UUID) async {
        defer { if generation == token { worker = nil } }
        while isActive, generation == token, let sample = pending {
            pending = nil
            let result: Result<TrafficWarningSnapshot, Error>
            if let heading = sample.heading {
                do { result = .success(try await store.load(latitude: sample.location.coordinate.latitude, longitude: sample.location.coordinate.longitude, heading: heading)) }
                catch { result = .failure(error) }
            } else { result = .success(TrafficWarningSnapshot(nodes: [], speedLimit: nil)) }
            guard !Task.isCancelled, isActive, generation == token else { return }
            // Bỏ kết quả lỗi thời khi GPS mới đã tới trong lúc truy vấn.
            guard pending == nil, now().timeIntervalSince(sample.location.timestamp) <= 10 else { continue }
            var candidates: [WarningCandidate] = []
            if case .success(let snapshot) = result, let heading = sample.heading {
                let coordinate = sample.location.coordinate
                let radius = max(1500, max(effectiveWarningDistance, effectiveAlertDistance))
                candidates = await Task.detached(priority: .userInitiated) {
                    WarningGeometry.candidates(nodes: snapshot.nodes, coordinate: coordinate, heading: heading, radius: radius)
                }.value
            }
            guard !Task.isCancelled, isActive, generation == token else { return }
            guard pending == nil, now().timeIntervalSince(sample.location.timestamp) <= 10 else { continue }
            apply(sample, result: result, candidates: candidates)
        }
    }

    private func apply(_ sample: Sample, result: Result<TrafficWarningSnapshot, Error>, candidates: [WarningCandidate]) {
        currentSpeed = sample.speed
        lastUpdatedAt = sample.location.timestamp; hasFreshLocation = true; hasSpeedMeasurement = sample.hasValidSpeed
        hasReliableHeading = sample.heading != nil
        let snapshot: TrafficWarningSnapshot
        switch result {
        case .failure(let error):
            currentSpeedLimit = nil; resetOverspeed(); upcomingWarnings = []; closestWarning = nil
            lastError = "Không thể đọc dữ liệu cảnh báo: \(error.localizedDescription)"
            return
        case .success(let value): snapshot = value; lastError = nil
        }
        currentSpeedLimit = snapshot.speedLimit.flatMap { $0 > 0 ? $0 : nil }
        let timestamp = sample.location.timestamp
        updateOverspeed(validSpeed: sample.hasValidSpeed, timestamp: timestamp)
        announced = announced.filter { timestamp.timeIntervalSince($0.value) >= 0 && timestamp.timeIntervalSince($0.value) < 300 }
        finalAnnouncements = finalAnnouncements.filter { timestamp.timeIntervalSince($0.value) >= 0 && timestamp.timeIntervalSince($0.value) < 300 }
        guard let heading = sample.heading else { upcomingWarnings = []; closestWarning = nil; return }
        _ = heading // Heading đã được kiểm tra khi tạo candidates.
        var warnings = candidates.map { candidate in
            WarningItem(id: candidate.id, node: candidate.node, distance: candidate.distance,
                        bearing: candidate.bearing, hasAnnounced: announced[candidate.id] != nil)
        }
        // Ưu tiên một cảnh báo điểm; audio vượt tốc độ chỉ phát nếu còn rảnh.
        var spokePoint = false
        for index in warnings.indices {
            let warning = warnings[index]
            // Biển cấm rẽ thiếu hướng: chỉ hiển thị tham khảo, không phát cảnh báo pháp lý.
            if (warning.node.type == .noLeftTurn || warning.node.type == .noRightTurn) && warning.node.bearing == nil { continue }
            if warning.distance <= effectiveAlertDistance && announced[warning.id] == nil {
                let result = announcer.announce(message(for: warning, final: false), category: category(for: warning.node.type), priority: .normal)
                if result == .suppressed { continue }
                if result == .accepted {
                    NavigationEvents.record(.warningTriggered)
                    announced[warning.id] = timestamp
                    spokePoint = true
                    warnings[index] = WarningItem(id: warning.id, node: warning.node, distance: warning.distance, bearing: warning.bearing, hasAnnounced: true)
                }
                break
            }
            let nodeLimit = warning.node.speedLimit.flatMap { $0 > 0 ? $0 : nil } ?? currentSpeedLimit
            if warning.distance < 100, announced[warning.id] != nil, finalAnnouncements[warning.id] == nil,
               let limit = nodeLimit, sample.hasValidSpeed, currentSpeed > Double(limit) + effectiveTolerance {
                let result = announcer.announce(message(for: warning, final: true), category: category(for: warning.node.type), priority: .high)
                if result == .suppressed { continue }
                if result == .accepted { finalAnnouncements[warning.id] = timestamp; spokePoint = true }
                break
            }
        }
        upcomingWarnings = warnings; closestWarning = warnings.first
        if !spokePoint { announceOverspeed(at: timestamp) }
    }

    private var effectiveTolerance: Double { overspeedTolerance.isFinite ? max(0, overspeedTolerance) : 5 }
    private var effectiveWarningDistance: Double { warningDistance.isFinite ? min(2000, max(0, warningDistance)) : 500 }
    private var effectiveAlertDistance: Double { alertDistance.isFinite ? min(2000, max(0, alertDistance)) : 300 }
    public var isClosestWithinWarningDistance: Bool { closestWarning.map { $0.distance <= effectiveWarningDistance } ?? false }

    private func updateOverspeed(validSpeed: Bool, timestamp: Date) {
        guard validSpeed, let limit = currentSpeedLimit, currentSpeed > Double(limit) + effectiveTolerance else { resetOverspeed(); return }
        if overspeedLimit != limit || lastOverspeedSample.map({ timestamp.timeIntervalSince($0) > 5 || timestamp < $0 }) ?? true {
            overspeedStart = timestamp; lastOverspeedAnnouncement = nil
        }
        overspeedLimit = limit; lastOverspeedSample = timestamp; isOverSpeeding = true
        overspeedingDuration = max(0, timestamp.timeIntervalSince(overspeedStart ?? timestamp))
    }
    private func announceOverspeed(at timestamp: Date) {
        guard isOverSpeeding, let limit = currentSpeedLimit,
              lastOverspeedAnnouncement.map({ timestamp.timeIntervalSince($0) >= 3 }) ?? true else { return }
        if announcer.announce("Bạn có thể đang vượt tốc độ. Giới hạn ước tính \(limit) ki-lô-mét trên giờ.", category: .overspeed, priority: .high) == .accepted {
            NavigationEvents.record(.warningTriggered)
            lastOverspeedAnnouncement = timestamp
        }
    }
    /// Không tiếp tục hiển thị tốc độ hoặc cảnh báo cũ khi GPS ngừng cập nhật.
    public func refreshFreshness() {
        guard isActive else { return }
        guard let timestamp = lastUpdatedAt, now().timeIntervalSince(timestamp) <= 10,
              now().timeIntervalSince(timestamp) >= -5 else {
            hasFreshLocation = false; hasSpeedMeasurement = false; currentSpeed = 0; currentSpeedLimit = nil; hasReliableHeading = false
            resetOverspeed(); upcomingWarnings = []; closestWarning = nil
            return
        }
    }
    private func resetOverspeed() {
        isOverSpeeding = false; overspeedingDuration = 0; overspeedStart = nil
        lastOverspeedSample = nil; lastOverspeedAnnouncement = nil; overspeedLimit = nil
    }

    /// Điểm phải ở phía trước (<60°); bearing biển nếu có phải khớp (<45°).
    public func filterByHeading(nodes: [TrafficNode], userLocation: CLLocation, userHeading: Double) -> [TrafficNode] {
        WarningGeometry.candidates(nodes: nodes, coordinate: userLocation.coordinate, heading: userHeading, radius: .infinity).map(\.node)
    }
    public func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double { WarningGeometry.bearing(from, to) }
    public func angleDifference(_ a: Double, _ b: Double) -> Double { WarningGeometry.difference(a, b) }
    public func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double { WarningGeometry.distance(from, to) }
    private func category(for type: NodeType) -> AlertCategory {
        switch type {
        case .speedCamera, .redLightCamera: return .camera
        case .speedLimit, .residentialIn, .residentialOut, .noOvertaking, .noLeftTurn, .noRightTurn: return .roadSign
        case .tollBooth: return .toll
        case .railwayCrossing: return .railway
        case .incident: return .general
        }
    }
    private func message(for warning: WarningItem, final: Bool) -> String {
        let name: String
        switch warning.node.type {
        case .speedCamera: name = "camera tốc độ"
        case .redLightCamera: name = "camera đèn đỏ"
        case .speedLimit: name = "biển tốc độ"
        case .residentialIn: name = "biển vào khu dân cư"
        case .residentialOut: name = "biển ra khu dân cư"
        case .tollBooth: name = "trạm thu phí"
        case .railwayCrossing: name = "giao cắt đường sắt"
        case .noOvertaking: name = "biển cấm vượt"
        case .noLeftTurn: name = "biển cấm rẽ trái"
        case .noRightTurn: name = "biển cấm rẽ phải"
        case .incident: name = "sự cố giao thông"
        }
        if final { return "Chú ý \(name) rất gần; bạn có thể đang vượt tốc độ." }
        return "Có thể có \(name) phía trước, cách khoảng \(Int(warning.distance.rounded())) mét."
    }
}
