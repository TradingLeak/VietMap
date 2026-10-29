import SwiftUI

struct NavigationBottomBar: View {
    let duration: TimeInterval
    let distance: Double
    let eta: Date?
    let progress: Double
    let onStop: () -> Void
    @AppStorage("vn.distanceUnit") private var unit = "km"
    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                metrics(includeETA: true)
                metrics(includeETA: false)
            }
            ProgressView(value: progress.isFinite ? min(1, max(0, progress)) : 0).tint(VNTheme.accent)
                .accessibilityLabel("Tiến độ hành trình")
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 20).fill(VNTheme.surface).shadow(color: VNTheme.shadow.opacity(0.18), radius: 12, y: 4))
    }
    private func metrics(includeETA: Bool) -> some View {
        HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NavigationFormat.duration(duration)).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(VNTheme.accent)
                    Text("THỜI GIAN CÒN LẠI").font(.system(size: 9, weight: .bold)).foregroundStyle(VNTheme.secondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(NavigationFormat.distance(distance, unit: unit)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(VNTheme.text)
                    Text("QUÃNG ĐƯỜNG").font(.system(size: 9, weight: .bold)).foregroundStyle(VNTheme.secondary)
                }
                if includeETA, let eta {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(eta.formatted(date: .omitted, time: .shortened)).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(VNTheme.text)
                        Text("DỰ KIẾN ĐẾN").font(.system(size: 9, weight: .bold)).foregroundStyle(VNTheme.secondary)
                    }
                }
                Button(action: onStop) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(VNTheme.onAccent)
                        .frame(width: 42, height: 42).background(Circle().fill(VNTheme.danger))
                }.accessibilityLabel("Dừng dẫn đường")
            }
    }

}
struct NavigationBottomBar_Previews: PreviewProvider {
    static var previews: some View { NavigationBottomBar(duration: 1200, distance: 12500, eta: Date(), progress: 0.4, onStop: {}).padding().previewLayout(.sizeThatFits) }
}
