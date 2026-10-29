import SwiftUI
import CoreLocation
import Combine

/// ObservableObject hỗ trợ iOS 16; vị trí do LocationManager dùng chung cung cấp.
@MainActor
public final class MapViewModel: ObservableObject {
    @Published public private(set) var heading: CLLocationDirection = 0
    @Published public private(set) var zoomLevel: Double = 17
    @Published public private(set) var pitch: CGFloat = 60
    @Published public private(set) var isFollowingUser = true
    @Published private(set) var isActive = false

    public var currentLocation: CLLocation? { locationManager.currentLocation }
    public var authorization: CLAuthorizationStatus { locationManager.authorizationStatus }
    public var locationError: String? { locationManager.errorMessage }
    private let locationManager: LocationManager
    private var subscriptions = Set<AnyCancellable>()

    public init(locationManager: LocationManager = .shared) {
        self.locationManager = locationManager
        // Chuyển tiếp thay đổi để SwiftUI cập nhật cả các thuộc tính tính toán.
        locationManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        locationManager.$course.sink { [weak self] course in
            guard let self, self.isFollowingUser else { return }
            self.setBearing(course)
        }.store(in: &subscriptions)
    }

    public func start() { isActive = true; locationManager.startTracking() }
    public func stop() { isActive = false; locationManager.stopTracking() }

    public func centerOnUser() {
        isFollowingUser = true
        setBearing(locationManager.course)
        locationManager.requestWhenInUseAuthorization()
    }

    public func setPitch(_ value: CGFloat) { pitch = min(60, max(0, value)) }
    public func setBearing(_ value: CLLocationDirection) {
        guard value.isFinite else { return }
        heading = (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
    public func setZoom(_ value: Double) {
        guard value.isFinite else { return }
        zoomLevel = min(20, max(0, value))
    }

    func stopFollowing() { isFollowingUser = false }
}
