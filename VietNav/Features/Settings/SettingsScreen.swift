import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    var isNavigating = false
    @AppStorage("vn.distanceUnit") private var unit = "km"
    @AppStorage("vn.mapAppearance") private var appearance = "system"
    @AppStorage("vn.haptics") private var haptics = true
    @State private var showAudio = false
    @State private var showOfflinePicker = false
    @State private var showTrafficPicker = false
    @State private var trafficFile: URL?
    @State private var confirmTrafficImport = false
    @StateObject private var trafficImport = TrafficDataImport()
    @ObservedObject private var offline = OfflineMapStore.shared
    @Environment(\.dismiss) private var dismiss
    init(isNavigating: Bool = false) { self.isNavigating = isNavigating }
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
                Section("BẢN ĐỒ OFFLINE") {
                    Button("Nhập bản đồ MBTiles…") { showOfflinePicker = true }
                        .disabled(offline.isImporting)
                    if offline.isImporting { ProgressView("Đang sao chép và kiểm tra bản đồ…") }
                    Toggle("Dùng bản đồ offline", isOn: Binding(get: { offline.isEnabled }, set: { offline.setEnabled($0) }))
                        .disabled(offline.styleURL == nil || offline.isImporting)
                    if let message = offline.message { Text(message).font(.caption) }
                    Text("Nhập MBTiles raster PNG/JPEG hoặc vector OpenMapTiles được phép sử dụng. Vector offline chưa có tên đường. Chỉ hiển thị vùng có trong tệp; tìm kiếm và tính tuyến vẫn cần mạng.")
                        .font(.caption).foregroundStyle(VNTheme.secondary)
                }
                Section("DỮ LIỆU BIỂN BÁO") {
                    Button("Nhập dữ liệu giao thông SQLite…") { showTrafficPicker = true }
                        .disabled(trafficImport.importing || isNavigating)
                    if trafficImport.importing { ProgressView("Đang nhập dữ liệu…") }
                    if let message = trafficImport.message { Text(message).font(.caption) }
                    Text("Không có sẵn dữ liệu biển báo toàn quốc. Dữ liệu OSM có thể thiếu, sai và sai chiều; không thay thế biển báo thực tế.")
                        .font(.caption).foregroundStyle(VNTheme.secondary)
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
            .alert("Thay dữ liệu OSM trên thiết bị?", isPresented: $confirmTrafficImport) {
                Button("Nhập dữ liệu", role: .destructive) { if let trafficFile { trafficImport.install(trafficFile) }; trafficFile = nil }
                Button("Hủy", role: .cancel) { trafficFile = nil }
            } message: {
                Text("Thao tác thay toàn bộ dữ liệu đường và điểm OSM hiện có; báo cáo người dùng được giữ lại. Chỉ nhập tệp bạn tin cậy khi không dẫn đường.")
            }
            .fileImporter(isPresented: $showTrafficPicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let file = urls.first { trafficFile = file; confirmTrafficImport = true }
                case .failure(let error): trafficImport.message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $showOfflinePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { offline.importFile(url) }
                case .failure(let error): offline.message = error.localizedDescription
                }
            }
        }
    }
}
struct SettingsScreen_Previews: PreviewProvider { static var previews: some View { SettingsScreen() } }
