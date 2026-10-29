import Foundation
import CoreLocation
import Combine
import UIKit

/// Nguồn vị trí dùng chung. ObservableObject thay cho @Observable để hỗ trợ iOS 16.
@MainActor
public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared: LocationManager = {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-use-simulator-location") { return LocationManager(simulateOnSimulator: false) }
        #endif
        return LocationManager()
    }()

    @Published public private(set) var currentLocation: CLLocation?
    @Published public private(set) var heading: CLHeading?
    @Published public private(set) var speed: Double = 0 // km/h, trung bình ba mẫu
    @Published public private(set) var course: Double = 0 // hướng đã kết hợp, độ
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus
    @Published public private(set) var isNavigating = false
    @Published public private(set) var errorMessage: String?

    private let manager: CLLocationManager
    private var speedSamples: [Double] = []
    private var trackingRequested = false
    private var isBackground = false
    private var planningRoute = false
    private var pendingAlwaysRequest = false
    private var notificationTokens: [NSObjectProtocol] = []
    #if targetEnvironment(simulator)
    private let simulateOnSimulator: Bool
    private var simulator: GPXLocationSimulator?
    #endif

    /// Simulator mặc định phát GPX đóng gói; truyền false để dùng vị trí do Xcode giả lập.
    public init(simulateOnSimulator: Bool = true) {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        #if targetEnvironment(simulator)
        self.simulateOnSimulator = simulateOnSimulator
        #endif
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 5
        manager.headingFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        isBackground = UIApplication.shared.applicationState == .background
        configureAccuracy()
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.setBackground(true) }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.setBackground(false) }
            }
        ]
    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Bắt đầu theo dõi khi có nhu cầu, không tự mở hộp thoại quyền.
    public func startTracking() {
        trackingRequested = true
        updateTracking()
    }

    /// Không dừng phiên dẫn đường đang hoạt động khi màn hình biến mất.
    public func stopTracking() {
        trackingRequested = false
        updateTracking()
    }

    /// Xin một GPS fix mới khi mở xem trước tuyến, thay vì đợi distanceFilter lúc rảnh.
    public func beginRoutePlanning() {
        planningRoute = true
        trackingRequested = true
        configureAccuracy()
        requestWhenInUseAuthorization()
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            #if targetEnvironment(simulator)
            if !simulateOnSimulator { manager.requestLocation() }
            #else
            manager.requestLocation()
            #endif
        }
    }

    public func endRoutePlanning() {
        planningRoute = false
        configureAccuracy()
    }

    public func requestWhenInUseAuthorization() {
        switch authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: showAuthorizationError()
        default: updateTracking()
        }
    }

    /// Gọi khi người dùng chủ động bắt đầu dẫn đường, trước khi ứng dụng xuống nền.
    public func startNavigation() {
        guard authorizationStatus != .denied, authorizationStatus != .restricted else {
            showAuthorizationError()
            return
        }
        isNavigating = true
        pendingAlwaysRequest = authorizationStatus != .authorizedAlways
        configureAccuracy()
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            requestAlwaysIfNeeded()
        }
        updateTracking()
    }

    public func stopNavigation() {
        isNavigating = false
        pendingAlwaysRequest = false
        manager.allowsBackgroundLocationUpdates = false
        configureAccuracy()
        updateTracking()
    }

    private func requestAlwaysIfNeeded() {
        // iOS chỉ hiển thị prompt nâng cấp khi trạng thái và thời điểm cho phép.
        guard isNavigating, pendingAlwaysRequest, authorizationStatus == .authorizedWhenInUse else { return }
        pendingAlwaysRequest = false
        manager.requestAlwaysAuthorization()
    }

    private func setBackground(_ background: Bool) {
        isBackground = background
        configureAccuracy()
        updateTracking()
    }

    private func configureAccuracy() {
        BatteryOptimizer.adjustAccuracy(manager, context: isNavigating ? .activeNavigation : (isBackground ? .backgroundIdle : .idle))
        if planningRoute && !isNavigating && !isBackground {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
        }
    }

    private func updateTracking() {
        let authorized = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        let shouldTrack = authorized && (trackingRequested || isNavigating)
        // Chỉ bật background location trong phiên dẫn đường được cấp quyền.
        manager.allowsBackgroundLocationUpdates = shouldTrack && isNavigating
        guard shouldTrack else {
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            speedSamples.removeAll()
            speed = 0
            #if targetEnvironment(simulator)
            simulator?.stop()
            #endif
            return
        }
        errorMessage = nil
        #if targetEnvironment(simulator)
        if simulateOnSimulator {
            if simulator == nil {
                simulator = GPXLocationSimulator { [weak self] location in self?.accept(location) }
            }
            if simulator?.start() != true {
                errorMessage = "Không thể tải tuyến GPX giả lập."
            }
            return
        }
        #endif
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    private func showAuthorizationError() {
        errorMessage = authorizationStatus == .restricted
            ? "Quyền vị trí bị hạn chế trên thiết bị này."
            : "Quyền vị trí bị từ chối. Hãy bật quyền trong Cài đặt."
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            // Không giữ trạng thái dẫn đường khi không còn quyền vị trí.
            isNavigating = false
            pendingAlwaysRequest = false
            currentLocation = nil
            heading = nil
            showAuthorizationError()
            configureAccuracy()
        } else if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            errorMessage = nil
            requestAlwaysIfNeeded()
        }
        updateTracking()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 { accept(location) }
    }

    private func accept(_ location: CLLocation) {
        currentLocation = location
        if location.speed < 0 || !location.speed.isFinite {
            // Không để một giá trị không hợp lệ tiếp tục hiển thị vận tốc cũ.
            speedSamples.removeAll()
            speed = 0
        } else {
            speedSamples.append(location.speed * 3.6)
            if speedSamples.count > 3 { speedSamples.removeFirst() }
            speed = speedSamples.reduce(0, +) / Double(speedSamples.count)
        }
        updateCourse()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading
        updateCourse()
    }

    private func updateCourse() {
        if speed > 5, let gpsCourse = currentLocation?.course, gpsCourse >= 0, gpsCourse.isFinite {
            course = gpsCourse
        } else if let compass = heading, compass.trueHeading >= 0, compass.trueHeading.isFinite {
            course = compass.trueHeading
        }
        // Không có giá trị hợp lệ: giữ hướng cuối cùng thay vì nhảy về 0.
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code != .locationUnknown {
            errorMessage = "Không thể lấy vị trí: \(error.localizedDescription)"
        }
    }
}
