import Foundation
import CoreLocation
import Combine

/// Nguồn vị trí cho giao diện: chỉ theo dõi khi người dùng chủ động cho phép.
@MainActor
final class MapModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLLocationDirection = 0
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var error: String?
    @Published var zoom: Double = 16
    @Published var pitch: CGFloat = 45
    @Published var followsLocation = true
    @Published var isDemo = false
    @Published var soundEnabled = true
    private let manager: CLLocationManager
    private var requested = false

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 5
    }
    func locate() {
        requested = true
        followsLocation = true
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: startUpdates()
        case .denied, .restricted: error = "VietNav chưa có quyền vị trí. Hãy kiểm tra Cài đặt → Quyền riêng tư & Bảo mật → Dịch vụ định vị."
        @unknown default: error = "Không thể xác định quyền vị trí."
        }
    }
    private func startUpdates() {
        error = nil
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }
    func stop() { manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); requested = false }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if requested && (authorization == .authorizedWhenInUse || authorization == .authorizedAlways) { startUpdates() }
        if authorization == .denied || authorization == .restricted { location = nil; if requested { error = "Quyền vị trí bị từ chối hoặc hạn chế." } }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return }
        location = fix
        if fix.speed >= 1.4, fix.course >= 0 { heading = fix.course }
        error = nil
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if (location?.speed ?? 0) < 1.4, newHeading.headingAccuracy >= 0, newHeading.trueHeading >= 0 { heading = newHeading.trueHeading }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code != .locationUnknown { self.error = "Không lấy được vị trí: \(error.localizedDescription)" }
    }
    func adjustZoom(_ amount: Double) { zoom = min(19, max(3, zoom + amount)) }
}
