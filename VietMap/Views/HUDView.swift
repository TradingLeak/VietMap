import SwiftUI
import UIKit

struct HUDView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var originalBrightness: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                HStack {
                    Label(model.mode == .demo ? "MÔ PHỎNG · KHÔNG PHẢI DỮ LIỆU THỰC" : "VIETMAP · HUD", systemImage: "location.north.fill")
                        .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(model.mode == .demo ? Palette.amber : .white.opacity(0.55))
                    Spacer()
                    Button { model.settings.mirrorHUD.toggle() } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").frame(width: 48, height: 44) }
                        .accessibilityLabel("Lật gương HUD")
                    Button { model.showHUD = false } label: { Image(systemName: "xmark").font(.headline).frame(width: 48, height: 44).background(.white.opacity(0.1), in: Circle()) }
                        .accessibilityLabel("Đóng HUD").accessibilityIdentifier("hud.close")
                }
                Group {
                    if geometry.size.width > geometry.size.height {
                        HStack(spacing: 35) { speed.frame(maxWidth: .infinity); details.frame(maxWidth: .infinity) }
                    } else { VStack(spacing: 32) { Spacer(minLength: 0); speed; details; Spacer(minLength: 0) } }
                }
                .scaleEffect(x: model.settings.mirrorHUD ? -1 : 1, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Chỉ tham khảo · luôn tuân thủ biển báo thực tế").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
            }.padding(24)
        }
        .foregroundStyle(.white).background(.black).preferredColorScheme(.dark)
        .statusBarHidden().persistentSystemOverlays(.hidden)
        .onAppear { originalBrightness = UIScreen.main.brightness; boostBrightness() }
        .onDisappear { restoreBrightness() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { boostBrightness() } else { restoreBrightness() } }
    }

    private var speed: some View {
        VStack(spacing: 0) {
            Text(model.snapshot.speedKmh.map { String(Int($0.rounded())) } ?? "– –")
                .font(.system(size: 155, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                .foregroundStyle(model.snapshot.isOverspeed ? Palette.accent : .white)
            Text("KM / H").font(.system(size: 14, weight: .semibold)).tracking(6).foregroundStyle(.white.opacity(0.45))
            if !model.snapshot.isReliable { Text("CHỜ TÍN HIỆU GPS").font(.caption.bold()).foregroundStyle(Palette.amber).padding(.top, 16) }
        }
    }

    private var details: some View {
        VStack(spacing: 22) {
            HStack(spacing: 18) {
                SpeedLimitSign(limit: model.snapshot.speedLimit, size: 82)
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.snapshot.isOverspeed ? "GIẢM TỐC" : "GIỚI HẠN ĐOẠN ĐƯỜNG").font(.system(size: 11, weight: .bold)).foregroundStyle(model.snapshot.isOverspeed ? Palette.accent : .white.opacity(0.45))
                    Text(model.snapshot.road?.name ?? "Chưa xác định").font(.headline).lineLimit(2)
                }
            }
            if let item = model.snapshot.upcoming.first {
                HStack(spacing: 16) {
                    Image(systemName: item.hazard.kind.symbol).font(.largeTitle).foregroundStyle(Palette.amber)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.hazard.title).font(.subheadline.bold())
                        Text("\(max(10, Int(item.distance / 10) * 10)) m").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.amber)
                    }
                    Spacer(minLength: 0)
                }.padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            } else { Text(model.displayDataset == nil ? "Chưa có dữ liệu cảnh báo thực" : "Chưa phát hiện cảnh báo phía trước").font(.caption).foregroundStyle(.white.opacity(0.45)) }
        }
    }

    private func boostBrightness() {
        if originalBrightness != nil { UIScreen.main.brightness = max(UIScreen.main.brightness, 0.85) }
    }
    private func restoreBrightness() {
        if let originalBrightness { UIScreen.main.brightness = originalBrightness }
    }
}
