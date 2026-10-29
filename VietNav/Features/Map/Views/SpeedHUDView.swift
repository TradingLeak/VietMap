import SwiftUI

struct SpeedHUDView: View {
    let currentSpeed: Double?
    let speedLimit: Int?
    let isOverSpeeding: Bool
    @AppStorage("vn.distanceUnit") private var unit = "km"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var factor: Double { unit == "mi" ? 0.621371 : 1 }
    private var speedLabel: String { currentSpeed.map { String(format: "%.0f", $0 * factor) } ?? "—" }
    var body: some View {
        HStack(spacing: -9) {
            VStack(spacing: -2) {
                Text(speedLabel).font(.system(size: 27, weight: .heavy, design: .rounded))
                Text(unit == "mi" ? "mph" : "km/h").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(VNTheme.onAccent)
            .frame(width: 68, height: 68)
            .background(Circle().fill(isOverSpeeding ? VNTheme.danger : VNTheme.accentDeep).overlay(Circle().stroke(VNTheme.onAccent, lineWidth: 3)))
            .scaleEffect(isOverSpeeding && pulse && !reduceMotion ? 1.06 : 1)
            .zIndex(1)
            if let limit = speedLimit {
                Text(String(format: "%.0f", Double(limit) * factor)).font(.system(size: 23, weight: .heavy, design: .rounded))
                    .foregroundStyle(VNTheme.text).frame(width: 60, height: 60)
                    .background(Circle().fill(VNTheme.surface).overlay(Circle().stroke(VNTheme.danger, lineWidth: 5)))
            }
        }
        .shadow(color: VNTheme.shadow.opacity(0.18), radius: 7, y: 3)
        .onAppear { updatePulse() }.onChange(of: isOverSpeeding) { _ in updatePulse() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tốc độ \(speedLabel) \(unit == "mi" ? "dặm" : "ki lô mét") một giờ. \(speedLimit.map { "Giới hạn ước tính \(Int((Double($0) * factor).rounded()))" } ?? "Chưa rõ giới hạn"). \(isOverSpeeding ? "Có thể vượt tốc độ." : "")")
    }
    private func updatePulse() {
        if isOverSpeeding && !reduceMotion { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
        else { pulse = false }
    }
}

struct SpeedHUDView_Previews: PreviewProvider {
    static var previews: some View { SpeedHUDView(currentSpeed: 65, speedLimit: 50, isOverSpeeding: true).padding().previewLayout(.sizeThatFits) }
}
