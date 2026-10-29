import SwiftUI
import AVFoundation
import VietMapCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var speech: SpeechService
    @State private var deleteTrips = false
    @State private var resetSettings = false

    var body: some View {
        Form {
            if !model.canEdit {
                Section { InformationBanner(text: "Cài đặt được khóa khi đang di chuyển hoặc chưa có tốc độ đáng tin cậy. Hãy dừng xe an toàn.", symbol: "hand.raised.fill") }
            }
            Section("Hiển thị") {
                Picker("Giao diện", selection: $model.settings.appearance) { ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) } }
                Picker("Nền bản đồ", selection: $model.settings.mapDisplay) { ForEach(MapDisplay.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Giữ màn hình sáng khi lái", isOn: $model.settings.keepScreenAwake)
                Toggle("Lật gương nội dung HUD", isOn: $model.settings.mirrorHUD)
            }.disabled(!model.canEdit)
            Section {
                Toggle("Cảnh báo bằng giọng nói", isOn: $model.settings.voiceEnabled)
                Picker("Giọng tiếng Việt", selection: $model.settings.voiceIdentifier) {
                    Text("Mặc định iOS").tag(String?.none)
                    ForEach(speech.vietnameseVoices, id: \.identifier) { voice in Text(voice.name).tag(Optional(voice.identifier)) }
                }
                VStack(alignment: .leading) {
                    Text("Tốc độ đọc").font(.subheadline)
                    Slider(value: $model.settings.speechRate, in: 0.35...0.6, step: 0.01)
                }
                Button { speech.preview() } label: { Label("Nghe thử giọng nói", systemImage: "speaker.wave.2.fill") }.disabled(!model.settings.voiceEnabled)
                Toggle("Rung khi bắt đầu quá tốc độ", isOn: $model.settings.hapticsEnabled)
            } header: { Text("Âm thanh") } footer: { Text("Dùng giọng hệ thống tiếng Việt. Tải giọng trước khi đi để dùng ngoại tuyến. Âm thanh qua loa/Bluetooth phụ thuộc định tuyến và âm lượng iOS.") }
                .disabled(!model.canEdit)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Dung sai cảnh báo"); Spacer(); Text("+\(Int(model.settings.overspeedTolerance)) km/h").monospacedDigit().foregroundStyle(Palette.accent) }
                    Slider(value: $model.settings.overspeedTolerance, in: 0...10, step: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Khoảng báo trước tối đa"); Spacer(); Text("\(Int(model.settings.maximumWarningDistance)) m").monospacedDigit().foregroundStyle(Palette.accent) }
                    Slider(value: $model.settings.maximumWarningDistance, in: 150...800, step: 50)
                }
                ForEach(HazardKind.allCases, id: \.self) { kind in
                    Toggle(isOn: Binding(get: { model.settings.enabledHazards.contains(kind) }, set: { enabled in
                        if enabled { model.settings.enabledHazards.insert(kind) } else { model.settings.enabledHazards.remove(kind) }
                    })) { Label(kind.title, systemImage: kind.symbol) }
                }
            } header: { Text("Cảnh báo giao thông") } footer: { Text("Dung sai chỉ thay đổi ngưỡng nhắc, KHÔNG thay đổi tốc độ được phép. Khoảng báo trước tự điều chỉnh theo tốc độ. Điểm cảnh báo cần đúng hướng và nằm trên hành lang đường dự đoán.") }
                .disabled(!model.canEdit)
            Section {
                NavigationLink { TrafficDataView() } label: {
                    Label { VStack(alignment: .leading, spacing: 4) { Text("Dữ liệu giao thông"); Text(model.hasRealData ? (model.importedDataset?.name ?? "Đã nhập") : "Chưa có dữ liệu thực").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "externaldrive.fill") }
                }.accessibilityIdentifier("settings.data")
                NavigationLink { PrivacyView() } label: { Label("Quyền riêng tư & giới hạn", systemImage: "hand.raised.fill") }
            }
            Section {
                Toggle("Ghi nhật ký hành trình", isOn: $model.settings.recordTrips).disabled(model.isDriving)
                Toggle("GPS khi khóa máy / chạy nền", isOn: $model.settings.backgroundLocation).disabled(model.isDriving)
                    .onChange(of: model.settings.backgroundLocation) { _, enabled in if enabled { model.location.requestAlways() } }
                Button("Mở quyền vị trí trong iOS") { model.openSystemSettings() }
            } header: { Text("Vị trí & hành trình") } footer: { Text("GPS nền tiêu hao pin, có thể hiện chỉ báo vị trí của iOS và không chạy nếu bạn buộc đóng ứng dụng. Chỉ bật khi cần. Thay đổi ghi nhật ký và GPS nền trước khi bắt đầu phiên.") }
                .disabled(!model.canEdit)
            Section("Trải nghiệm") {
                Button {
                    if model.mode == .demo { model.stopDriving() } else { Task { await model.startDemo() } }
                } label: { Label(model.mode == .demo ? "Kết thúc mô phỏng" : "Chạy mô phỏng an toàn", systemImage: "play.circle.fill") }
                    .disabled(model.mode == .live || model.isBusy || !model.isReady)
                Text("Mô phỏng không xin GPS, không dùng dữ liệu thật và được đánh dấu riêng trong nhật ký.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Xóa toàn bộ hành trình", role: .destructive) { deleteTrips = true }.disabled(!model.canManageData)
                Button("Khôi phục cài đặt mặc định") { resetSettings = true }.disabled(!model.canManageData)
            }
            Section {
                HStack { Text("VietMap"); Spacer(); Text(version).foregroundStyle(.secondary) }
                if let sourceURL = URL(string: "https://github.com/TradingLeak/VietMap") { Link("Mã nguồn & hướng dẫn build IPA", destination: sourceURL) }
                Text("Dự án độc lập. Không liên kết với VIETMAP hoặc VietHUD. Không sao chép dữ liệu, âm thanh hay mã nguồn chưa có quyền sử dụng.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cài đặt")
        .confirmationDialog("Xóa vĩnh viễn mọi hành trình trên thiết bị?", isPresented: $deleteTrips, titleVisibility: .visible) {
            Button("Xóa tất cả hành trình", role: .destructive) { Task { await model.deleteAllTrips() } }
        }
        .confirmationDialog("Đặt lại cài đặt? Dữ liệu giao thông và hành trình vẫn được giữ.", isPresented: $resetSettings, titleVisibility: .visible) {
            Button("Khôi phục mặc định") { model.settings = AppSettings() }
        }
    }

    private var version: String {
        "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))"
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Trên thiết bị của bạn") {
                Text("Vị trí GPS được dùng cho tốc độ, cảnh báo và nhật ký. Nhật ký nằm trong vùng dữ liệu riêng của ứng dụng, được bảo vệ bằng cơ chế bảo vệ tệp của iOS sau lần mở khóa đầu tiên. Không có tài khoản, quảng cáo hoặc SDK phân tích của dự án.")
                Text("Dữ liệu hành trình có thể nằm trong bản sao lưu thiết bị theo cài đặt iCloud của bạn. Dữ liệu giao thông tải lại được được loại khỏi sao lưu. Gỡ ứng dụng sẽ xóa dữ liệu cục bộ; nên xuất tệp quan trọng trước.")
                Text("Bản xuất tạm trên máy được dọn khi mở lại ứng dụng hoặc xóa hành trình tương ứng. Bản đã chia sẻ ra Tệp, iCloud hoặc dịch vụ khác không thể được ứng dụng thu hồi; bạn cần xóa riêng tại nơi đã nhận.")
            }
            Section("Khi sử dụng mạng") {
                Text("Apple MapKit gửi truy vấn tìm kiếm và vị trí nguồn/đích tới dịch vụ Apple khi bạn yêu cầu tính tuyến. Nền bản đồ do Apple cung cấp theo chính sách riêng của Apple. Dự án không thể cam kết dịch vụ bên thứ ba không xử lý dữ liệu.")
                Text("Tải dữ liệu chỉ bắt đầu sau khi bạn nhập URL HTTPS và mã SHA-256. Máy chủ đó có thể thấy IP của bạn. SHA-256 kiểm tra toàn vẹn, không chứng minh nguồn dữ liệu đáng tin hoặc có giấy phép.")
            }
            Section("Giới hạn quan trọng") {
                Text("GPS có sai số. Không hiển thị giới hạn nếu vị trí cũ hơn 10 giây, sai số vượt 50 mét, thiếu hướng chạy hoặc không ghép được đoạn đường đủ tin cậy. Đường song song, nút giao, hầm và dữ liệu cũ có thể làm thiếu cảnh báo.")
                Text("Dữ liệu cảnh báo và sơ đồ đường đã nhập chạy ngoại tuyến. Apple Maps không được tải trước bởi ứng dụng; tìm tuyến, tìm kiếm và tính lại tuyến cần Internet và có thể không được hỗ trợ tại mọi địa phương.")
                Text("Không có radar, nhận dạng biển báo bằng camera, thông tin phạt nguội cá nhân, làn đường chính xác, CarPlay hay dữ liệu VIETMAP thương mại đi kèm. Không có cam kết ứng dụng không có lỗi hoặc thay thế thiết bị an toàn.")
                Text("Luôn quan sát biển báo thực tế. Cài đặt hoặc đổi tuyến khi xe đã dừng. Tuân thủ pháp luật và điều kiện sử dụng dữ liệu tại nơi bạn di chuyển.")
            }
        }.navigationTitle("Quyền riêng tư").navigationBarTitleDisplayMode(.inline)
    }
}
