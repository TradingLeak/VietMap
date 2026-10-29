import SwiftUI

enum VNTheme {
    // Asset catalog thuộc bundle của Swift Package.
    static let accent = Color("VNAccent", bundle: .module)
    static let accentDeep = Color("VNAccentDeep", bundle: .module)
    static let surface = Color("VNSurface", bundle: .module)
    static let text = Color("VNText", bundle: .module)
    static let secondary = Color("VNSecondary", bundle: .module)
    static let border = Color("VNBorder", bundle: .module)
    static let danger = Color("VNDanger", bundle: .module)
    static let warning = Color("VNWarning", bundle: .module)
    static let onAccent = Color("VNOnAccent", bundle: .module)
    static let canvas = Color("VNCanvas", bundle: .module)
    static let shadow = Color("VNShadow", bundle: .module)
}

enum NavigationFormat {
    static func distance(_ meters: Double, unit: String = "km") -> String {
        let distance = meters.isFinite ? max(0, meters) : 0
        if unit == "mi" {
            let miles = distance / 1609.344
            return miles >= 0.1 ? String(format: "%.1f mi", miles) : "\(Int((distance * 3.28084).rounded())) ft"
        }
        return distance >= 1000 ? String(format: "%.1f km", distance / 1000) : "\(Int(distance.rounded())) m"
    }
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let minutes = max(0, Int((min(seconds, 3_600_000) / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60) giờ \(minutes % 60) phút" : "\(minutes) phút"
    }
}
