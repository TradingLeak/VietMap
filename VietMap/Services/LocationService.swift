import CoreLocation
import Combine
import VietMapCore

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var precise = true
    @Published private(set) var errorMessage: String?
    var onFix: ((LocationFix) -> Void)?
    var onDenied: (() -> Void)?
    private let manager = CLLocationManager()
    private var wantsUpdates = false
    private var wantsBackground = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 3
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
    }

    func start(background: Bool) {
        wantsUpdates = true
        wantsBackground = background
        errorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .denied, .restricted:
            errorMessage = "Quyền vị trí đang tắt. Bạn có thể bật lại trong Cài đặt iOS."
            onDenied?()
        @unknown default: onDenied?()
        }
    }

    func configureBackground(_ enabled: Bool) {
        wantsBackground = enabled
        manager.allowsBackgroundLocationUpdates = wantsUpdates && enabled
        manager.showsBackgroundLocationIndicator = wantsUpdates && enabled
    }

    func requestAlways() {
        if manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }

    func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    private func beginUpdates() {
        configureBackground(wantsBackground)
        manager.startUpdatingLocation()
    }

    // Delegate requirements are nonisolated. Only Sendable snapshots cross to the UI actor.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }

    private func authorizationChanged() {
        authorization = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
        guard wantsUpdates else { return }
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .denied, .restricted:
            errorMessage = "Không có quyền vị trí. Phiên lái xe đã dừng."
            stop()
            onDenied?()
        default: break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.sorted(by: { $0.timestamp < $1.timestamp }).map { value in
            LocationFix(coordinate: Coordinate(value.coordinate),
                        speedMPS: value.speed >= 0 && (0...5).contains(value.speedAccuracy) ? value.speed : nil,
                        heading: value.course >= 0 && (0...45).contains(value.courseAccuracy) ? value.course : nil,
                        horizontalAccuracy: value.horizontalAccuracy, timestamp: value.timestamp)
        }
        Task { @MainActor [weak self] in
            guard let self, self.wantsUpdates else { return }
            self.errorMessage = nil
            for fix in fixes { self.onFix?(fix) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self, self.wantsUpdates else { return }
            if denied {
                self.errorMessage = "iOS từ chối quyền vị trí."
                self.stop()
                self.onDenied?()
            } else {
                self.errorMessage = "Đang tìm lại tín hiệu GPS. Hãy đặt điện thoại ở nơi thoáng."
            }
        }
    }
}
