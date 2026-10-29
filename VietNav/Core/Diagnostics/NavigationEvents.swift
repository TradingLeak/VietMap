import OSLog

/// Chỉ ghi tên sự kiện cố định vào unified log cục bộ; không có SDK hay upload.
enum NavigationEvents {
    enum Event: String { case navigationStart = "navigation_start", warningTriggered = "warning_triggered", routeRecalculated = "route_recalculated" }
    private static let logger = Logger(subsystem: "vn.vietnav.app", category: "navigation")
    static func record(_ event: Event) { logger.info("\(event.rawValue, privacy: .public)") }
}
