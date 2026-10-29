import Foundation
import UIKit
import UserNotifications
import ActivityKit
import NavigationActivityShared

/// Hoạt động nhờ Core Location, không hứa hẹn hệ thống cấp thời gian nền vô hạn.
@MainActor
final class BackgroundTaskManager {
    private var notifiedStep: String?
    private let center = UNUserNotificationCenter.current()
    private var live: AnyObject?
    private var lastLiveUpdate = Date.distantPast
    private var lastLiveStep: String?

    func start(engine: NavigationEngine) {
        notifiedStep = nil; lastLiveStep = nil; lastLiveUpdate = .distantPast
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if #available(iOS 16.1, *) {
            let controller = NavigationLiveActivity()
            live = controller
            controller.start(state: state(engine))
        }
    }
    func update(engine: NavigationEngine) {
        guard engine.isNavigating else { return }
        let key = "\(engine.currentRoute?.id.uuidString ?? "")/\(engine.currentStepIndex)"
        if #available(iOS 16.1, *), let live = live as? NavigationLiveActivity,
           key != lastLiveStep || Date().timeIntervalSince(lastLiveUpdate) >= 15 {
            lastLiveStep = key; lastLiveUpdate = Date()
            live.update(state(engine))
        }
        guard UIApplication.shared.applicationState == .background,
              engine.distanceToNextManeuver > 0, engine.distanceToNextManeuver <= 200,
              let step = engine.currentStep, step.maneuver != .arrive, step.maneuver != .depart,
              notifiedStep != key else { return }
        notifiedStep = key
        notify(title: "Sắp đến điểm rẽ", body: step.instruction, id: "vietnav-turn")
    }
    func arrived() {
        if UIApplication.shared.applicationState == .background {
            notify(title: "Đã đến nơi", body: "Hành trình đã hoàn thành.", id: "vietnav-arrival")
        }
        endLive()
    }
    func stop() {
        center.removePendingNotificationRequests(withIdentifiers: ["vietnav-turn", "vietnav-arrival"])
        endLive(); notifiedStep = nil
    }
    private func endLive() {
        if #available(iOS 16.1, *), let live = live as? NavigationLiveActivity { live.end() }
        live = nil
    }
    private func notify(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { _ in }
    }
    @available(iOS 16.1, *)
    private func state(_ engine: NavigationEngine) -> NavigationActivityAttributes.ContentState {
        let maneuver = engine.currentStep?.maneuver
        let icon: String
        switch maneuver {
        case .turnLeft: icon = "arrow.turn.up.left"
        case .turnRight: icon = "arrow.turn.up.right"
        case .slightLeft: icon = "arrow.up.left"
        case .slightRight: icon = "arrow.up.right"
        case .uTurn: icon = "arrow.uturn.down"
        case .roundabout, .exitRoundabout: icon = "arrow.triangle.2.circlepath"
        case .arrive: icon = "mappin.and.ellipse"
        default: icon = "arrow.up"
        }
        return .init(distanceRemaining: engine.distanceRemaining, distanceToManeuver: engine.distanceToNextManeuver,
                     durationRemaining: engine.durationRemaining, currentInstruction: engine.currentStep?.instruction ?? "Tiếp tục đi",
                     nextManeuverIcon: icon)
    }
}

@available(iOS 16.1, *)
@MainActor
private final class NavigationLiveActivity {
    private var activity: Activity<NavigationActivityAttributes>?
    private var work: Task<Void, Never>?
    func start(state: NavigationActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Không đưa tên địa điểm/tọa độ lên màn hình khóa.
        activity = try? Activity.request(attributes: NavigationActivityAttributes(destinationName: "Điểm đến"), contentState: state, pushType: nil)
    }
    func update(_ state: NavigationActivityAttributes.ContentState) {
        guard let activity else { return }
        let previous = work
        work = Task { await previous?.value; await activity.update(using: state) }
    }
    func end() {
        guard let activity else { return }
        self.activity = nil
        let previous = work
        work = Task { await previous?.value; await activity.end(dismissalPolicy: .immediate) }
    }
}
