import Foundation

public enum AlertTemplate {
    public static func upcomingSpeedCamera(distance: Int, speedLimit: Int) -> String {
        "Phía trước \(distance) mét có camera bắn tốc độ, giới hạn \(speedLimit) ki-lô-mét một giờ"
    }
    public static func upcomingRedLightCamera(distance: Int) -> String { "Phía trước \(distance) mét có camera phạt nguội đèn đỏ" }
    public static func enteringResidentialArea() -> String { "Chú ý, bạn đang vào khu đông dân cư" }
    public static func exitingResidentialArea() -> String { "Bạn đã ra khỏi khu đông dân cư" }
    public static func upcomingTollBooth(distance: Int) -> String { "Phía trước \(distance) mét có trạm thu phí" }
    public static func upcomingRailwayCrossing(distance: Int) -> String { "Chú ý, phía trước \(distance) mét có đường ngang qua đường sắt" }
    public static func overspeedWarning(current: Int, limit: Int) -> String { "Bạn đang vượt quá tốc độ cho phép. Tốc độ tối đa \(limit) ki-lô-mét một giờ" }
    public static func turnInstruction(distance: Int, direction: String, street: String) -> String {
        let road = street.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = road.isEmpty ? direction : "\(direction) vào \(road)"
        if distance >= 1000 { return String(format: "Sau %.1f ki-lô-mét, %@", locale: Locale(identifier: "vi_VN"), Double(distance) / 1000, action) }
        if distance >= 100 { return "Sau \(distance) mét, \(action)" }
        return "\(direction) ngay"
    }
    public static func arriveAtDestination() -> String { "Bạn đã đến nơi. Kết thúc dẫn đường" }
    public static func recalculatingRoute() -> String { "Đang tính lại lộ trình" }
}
