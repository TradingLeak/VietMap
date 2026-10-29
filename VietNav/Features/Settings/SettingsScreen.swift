import SwiftUI

struct SettingsScreen: View {
    @AppStorage("vn.distanceUnit") private var unit = "km"
    @AppStorage("vn.mapAppearance") private var appearance = "system"
    @AppStorage("vn.haptics") private var haptics = true
    @State private var showAudio = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            Form {
                Section("CÁ NHÂN HÓA") {
                    Button { showAudio = true } label: { Label("Giọng nói & âm thanh", systemImage: "speaker.wave.2.fill") }
                    Picker("Đơn vị", selection: $unit) {
                        Text("Ki-lô-mét / km/h").tag("km")
                        Text("Dặm / mph").tag("mi")
                    }
                    Picker("Giao diện bản đồ", selection: $appearance) {
                        Text("Theo hệ thống").tag("system")
                        Text("Sáng").tag("light")
                        Text("Tối").tag("dark")
                    }
                    Toggle("Rung khi cảnh báo", isOn: $haptics)
                }
                Section("DỮ LIỆU & QUYỀN RIÊNG TƯ") {
                    Text("Tìm kiếm dùng Nominatim; tính tuyến gửi vị trí và điểm đến tới máy chủ OSRM. Báo cáo chỉ lưu trên thiết bị.")
                        .font(.caption).foregroundStyle(VNTheme.secondary)
                    Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                }
                Section { Text("VietNav · Bản thử nghiệm").font(.caption).foregroundStyle(VNTheme.secondary) }
            }
            .navigationTitle("Cài đặt").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
            .sheet(isPresented: $showAudio) { AudioSettingsView() }
        }
    }
}
struct SettingsScreen_Previews: PreviewProvider { static var previews: some View { SettingsScreen() } }
