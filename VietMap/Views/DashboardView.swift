import SwiftUI
import VietMapCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var speech: SpeechService
    @EnvironmentObject private var navigation: NavigationService

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if model.mode == .demo {
                    InformationBanner(text: "Đang mô phỏng · vị trí, camera và biển báo là giả lập. Không dùng dữ liệu này khi lái xe thật.", symbol: "play.circle.fill")
                }
                if !model.canEdit { InformationBanner(text: "Đang di chuyển. Hãy dừng xe an toàn trước khi thay đổi cài đặt.", symbol: "hand.raised.fill") }
                SpeedPanel()
                if let progress = navigation.progress, navigation.activeRoute != nil {
                    HStack(spacing: 14) {
                        Image(systemName: progress.hasArrived ? "flag.checkered" : "arrow.triangle.turn.up.right.diamond.fill").font(.title).foregroundStyle(Palette.mint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(progress.hasArrived ? "Bạn đã đến gần điểm đến" : (progress.nextInstruction ?? "Tiếp tục theo tuyến")).font(.headline)
                            Text(progress.isOffRoute ? "Đang kiểm tra và tính lại tuyến…" : "Còn \(DisplayFormat.distance(progress.remainingMetres)) đến điểm đến").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.panel()
                }
                MapPreview().frame(height: 225).clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .topLeading) {
                        Label(model.settings.mapDisplay == .offline ? "SƠ ĐỒ NGOẠI TUYẾN" : "APPLE MAPS", systemImage: "map.fill")
                            .font(.system(size: 10, weight: .bold)).padding(10).background(.regularMaterial, in: Capsule()).padding(12)
                    }
                warnings
                controls
                if model.mode == .idle {
                    Button { Task { await model.startDemo() } } label: {
                        Label("Trải nghiệm mô phỏng", systemImage: "play.circle").font(.subheadline.bold()).padding(10)
                    }.disabled(model.isBusy || !model.isReady).accessibilityIdentifier("dashboard.demo")
                }
                if let message = location.errorMessage, model.mode == .live {
                    InformationBanner(text: message, symbol: "location.slash.fill")
                    Button("Mở Cài đặt iOS") { model.openSystemSettings() }
                }
                if !location.precise, model.mode == .live { InformationBanner(text: "Hãy bật Vị trí chính xác trong Cài đặt iOS để cảnh báo giao thông có thể hoạt động.") }
                if let warning = speech.warning { InformationBanner(text: warning, symbol: "speaker.slash.fill") }
                if let warning = model.storageWarning { InformationBanner(text: warning, symbol: "externaldrive.badge.exclamationmark") }
                if let notice = model.notice {
                    HStack(alignment: .top) {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                        Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Đóng thông báo")
                    }.padding(.horizontal, 4)
                }
                Text("Trợ lý tham khảo, không thay thế biển báo và sự quan sát của người lái.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.bottom, 8)
            }.padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }.background(Palette.background).toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "location.north.fill").foregroundStyle(Palette.accent).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VIETMAP").font(.system(size: 20, weight: .black, design: .rounded)).tracking(2)
                    Text("TRỢ LÝ HÀNH TRÌNH").font(.system(size: 8, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.mode == .demo ? Palette.amber : (model.snapshot.isReliable ? Palette.mint : .secondary)).frame(width: 6, height: 6)
                Text(model.statusTitle).font(.system(size: 10, weight: .bold)).accessibilityIdentifier("dashboard.status")
            }.padding(.horizontal, 11).padding(.vertical, 9).background(.primary.opacity(0.05), in: Capsule())
        }.padding(.vertical, 5)
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("PHÍA TRƯỚC").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                if !model.snapshot.upcoming.isEmpty { Text("\(model.snapshot.upcoming.count) điểm").font(.caption).foregroundStyle(Palette.amber) }
            }
            if model.snapshot.upcoming.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.displayDataset == nil ? "externaldrive.badge.questionmark" : "eye").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.displayDataset == nil ? "Chưa có dữ liệu giao thông" : (model.snapshot.isReliable ? "Chưa phát hiện cảnh báo" : "Đang chờ vị trí hợp lệ")).font(.subheadline.bold())
                        Text(model.displayDataset == nil ? "Nhập dữ liệu có giấy phép trong Cài đặt → Dữ liệu giao thông." : "Không có cảnh báo không có nghĩa là tuyến đường không có rủi ro.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(model.snapshot.upcoming.prefix(3)) { item in HazardRow(item: item) }
            }
        }.panel()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if model.isDriving {
                HStack(spacing: 12) {
                    Button { model.showHUD = true } label: { Label("Chế độ HUD", systemImage: "rectangle.on.rectangle").frame(maxWidth: .infinity).padding(.vertical, 16).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)) }
                        .font(.subheadline.bold()).accessibilityIdentifier("dashboard.hud")
                    Button { model.settings.voiceEnabled.toggle() } label: { Image(systemName: model.settings.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width: 56, height: 52).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)) }
                        .accessibilityLabel(model.settings.voiceEnabled ? "Tắt giọng nói" : "Bật giọng nói")
                }
                PrimaryButton(title: model.mode == .demo ? "Kết thúc mô phỏng" : "Kết thúc hành trình", symbol: "stop.fill", destructive: true) { model.stopDriving() }
                    .accessibilityIdentifier("dashboard.stop")
            } else {
                PrimaryButton(title: model.isBusy ? "Đang chuẩn bị…" : "Bắt đầu lái xe", symbol: "location.fill") { Task { await model.startDriving() } }
                    .disabled(model.isBusy || !model.isReady).opacity(model.isBusy ? 0.5 : 1).accessibilityIdentifier("dashboard.start")
            }
        }
    }
}

struct SpeedPanel: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TỐC ĐỘ GPS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model.snapshot.speedKmh.map { String(Int($0.rounded())) } ?? "– –")
                            .font(.system(size: 92, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
                            .foregroundStyle(model.snapshot.isOverspeed ? Palette.accent : .primary).contentTransition(.numericText())
                            .accessibilityIdentifier("dashboard.speed")
                        Text("km/h").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    SpeedLimitSign(limit: model.snapshot.speedLimit)
                    Text("GIỚI HẠN").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                }
            }
            Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.snapshot.isOverspeed ? "exclamationmark.triangle.fill" : "road.lanes").foregroundStyle(model.snapshot.isOverspeed ? Palette.accent : Palette.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.snapshot.isOverspeed ? "Giảm tốc độ an toàn" : (model.snapshot.road?.name ?? (model.isDriving ? "Chưa xác định đoạn đường" : "Sẵn sàng cho hành trình mới")))
                        .font(.subheadline.bold()).lineLimit(2)
                    Text(model.snapshot.speedLimit == nil ? "Không suy đoán giới hạn khi chưa đủ dữ liệu" : "Giới hạn từ bộ dữ liệu đã nhập · cần đối chiếu biển báo")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let trip = model.currentTrip {
                HStack {
                    StatLabel(value: DisplayFormat.distance(trip.distanceMetres), title: "Quãng đường")
                    StatLabel(value: DisplayFormat.duration(trip.duration), title: "Thời gian")
                    StatLabel(value: "\(Int(trip.maximumSpeedKmh)) km/h", title: "Cao nhất")
                }.padding(.top, 2)
            }
        }.panel().overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(model.snapshot.isOverspeed ? Palette.accent : .clear, lineWidth: 2))
    }
}
