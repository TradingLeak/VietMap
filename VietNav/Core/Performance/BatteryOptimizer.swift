import Foundation
import CoreLocation
import Combine

public enum NavigationContext { case activeNavigation, idle, backgroundIdle }

/// Không giảm chất lượng GPS khi dẫn đường: cảnh báo an toàn cần dữ liệu mới.
@MainActor
public final class BatteryOptimizer: ObservableObject {
    public static let shared = BatteryOptimizer()
    @Published public private(set) var reducedRendering = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()
        let center = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    private func refresh() {
        let info = ProcessInfo.processInfo
        reducedRendering = info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
    }
    public static func adjustAccuracy(_ manager: CLLocationManager, context: NavigationContext) {
        switch context {
        case .activeNavigation:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation; manager.distanceFilter = 5
        case .idle:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters; manager.distanceFilter = 100
        case .backgroundIdle:
            manager.desiredAccuracy = kCLLocationAccuracyKilometer; manager.distanceFilter = 500
        }
    }
}
