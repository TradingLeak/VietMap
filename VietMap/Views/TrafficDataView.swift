import SwiftUI
import UniformTypeIdentifiers
import VietMapCore

struct TrafficDataView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showImporter = false
    @State private var confirmRemove = false
    @State private var remoteURL = ""
    @State private var checksum = ""
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                InformationBanner(text: "Chỉ nhập dữ liệu bạn có quyền sử dụng. Bản cài đặt không bao gồm cơ sở dữ liệu camera hoặc tốc độ thương mại của bên thứ ba.", symbol: "checkmark.shield.fill", color: Palette.mint)
                if !model.canManageData { Text(model.isBusy ? "Đang xử lý dữ liệu…" : "Kết thúc phiên lái xe trước khi quản lý dữ liệu.").font(.caption).foregroundStyle(Palette.amber) }
            }
            if let dataset = model.importedDataset {
                Section("Bộ dữ liệu hiện tại") {
                    LabeledContent("Tên", value: dataset.name)
                    LabeledContent("Phiên bản", value: dataset.version)
                    LabeledContent("Loại", value: dataset.isDemo ? "Mô phỏng · KHÔNG dùng lái thật" : "Nguồn do người dùng cung cấp")
                    LabeledContent("Cập nhật") { Text(dataset.updatedAt, style: .date) }
                    LabeledContent("Đoạn đường", value: "\(dataset.roads.count)")
                    LabeledContent("Điểm cảnh báo", value: "\(dataset.hazards.count)")
                    if Date().timeIntervalSince(dataset.updatedAt) > 90 * 86_400 { Text("Dữ liệu đã hơn 90 ngày. Hãy kiểm tra bản cập nhật với nhà cung cấp.").font(.caption).foregroundStyle(Palette.amber) }
                }
                Section("Nguồn & giấy phép") {
                    LabeledContent("Nhà cung cấp", value: dataset.source.name)
                    LabeledContent("Giấy phép", value: dataset.source.license)
                    Text(dataset.source.attribution).font(.footnote).textSelection(.enabled)
                    if let url = URL(string: dataset.source.url) { Link("Xem nguồn dữ liệu", destination: url) }
                    Text("Việc tệp khai báo giấy phép không thay thế việc xác minh quyền sử dụng của bạn.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section { ContentUnavailableView("Chưa có dữ liệu thực", systemImage: "externaldrive", description: Text("GPS và mô phỏng vẫn sử dụng được. Ứng dụng sẽ không tự đặt giới hạn tốc độ hoặc báo camera giả.")) }
            }
            Section {
                Button { showImporter = true } label: { Label("Nhập tệp JSON", systemImage: "square.and.arrow.down") }
                    .disabled(!model.canManageData).accessibilityIdentifier("data.import")
                Text("Schema VietMap v1 · tối đa 32 MB · 100.000 đoạn đường và 100.000 điểm. Kiểm tra đầy đủ trước khi thay thế nguyên tử dữ liệu cũ.").font(.caption).foregroundStyle(.secondary)
                NavigationLink("Định dạng dữ liệu & cách chuyển CSV") { DataFormatView() }
            } header: { Text("Nhập từ ứng dụng Tệp") }
            Section {
                TextField("https://…/traffic.json", text: $remoteURL).keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(!model.canManageData)
                TextField("SHA-256 (64 ký tự)", text: $checksum, axis: .vertical).font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!model.canManageData)
                if downloadTask != nil {
                    HStack { ProgressView(); Text("Đang tải và kiểm tra…"); Spacer(); Button("Hủy") { downloadTask?.cancel() } }
                } else {
                    Button("Tải, kiểm tra và thay thế dữ liệu") {
                        downloadTask = Task {
                            await model.importRemote(url: remoteURL, checksum: checksum)
                            downloadTask = nil
                        }
                    }.disabled(!model.canManageData || remoteURL.isEmpty || checksum.count != 64)
                }
            } header: { Text("Cập nhật qua HTTPS") } footer: { Text("Lấy mã SHA-256 từ kênh đáng tin cậy, độc lập với tệp tải. Kiểm tra toàn vẹn không phải chữ ký xác thực. Không tự động tải URL chưa được bạn chấp thuận; không nhập thông tin đăng nhập vào URL.") }
            if model.importedDataset != nil {
                Section { Button("Xóa dữ liệu đã nhập", role: .destructive) { confirmRemove = true }.disabled(!model.canManageData) }
            }
        }
        .navigationTitle("Dữ liệu giao thông").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await model.importFile(url) } }
            case .failure(let error): model.errorMessage = "Không mở được tệp: \(error.localizedDescription)"
            }
        }
        .confirmationDialog("Xóa bộ dữ liệu đã nhập? Dữ liệu mô phỏng đi kèm vẫn được giữ.", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Xóa dữ liệu", role: .destructive) { Task { await model.removeDataset() } }
        }
        .onDisappear { downloadTask?.cancel() }
    }
}

struct DataFormatView: View {
    var body: some View {
        List {
            Section("VietMap JSON · schemaVersion 1") {
                Text("Tệp UTF-8 chứa: schemaVersion, id, version, name, updatedAt (ISO-8601 UTC), source, isDemo, roads và hazards. Mỗi ID phải duy nhất trong nhóm. isDemo là trường bắt buộc.")
                Text("source: name, url HTTPS, license, attribution. Mỗi đoạn đường: id, name, start/end (latitude, longitude), direction (both/forward/backward), speedLimit (số nguyên km/h hoặc null nếu không biết).")
                Text("Mỗi cảnh báo: id, kind, name, coordinate, heading (hướng DI CHUYỂN của xe, 0–359 hoặc null), speedLimit (hoặc null), roadID (hoặc null), isEnd (true/false).")
                Text("kind: camera, speedLimit, residential, noOvertaking, toll, trafficLight, danger, restArea, tunnel. Không lấy giới hạn của camera hoặc biển phía trước làm giới hạn của đoạn đường hiện tại.")
            }
            Section("Chuẩn bị trên máy tính") {
                Text("Trong kho mã nguồn, xem docs/DATA_FORMAT.md và scripts/convert_csv.py. Bộ chuyển đổi dùng Python tiêu chuẩn, kiểm tra tọa độ/ID/hướng/giấy phép, tạo JSON và in SHA-256.")
                Text("Không nhập trực tiếp .bin của VietHUD. Cần xuất từ nguồn hợp pháp sang schema v1 và tự xác minh quy ước hướng camera, phạm vi, điều kiện và loại xe. Không sao chép dữ liệu độc quyền chỉ vì tệp được công khai trên GitHub.")
            }
            Section("Mô phỏng") {
                Text("VietMap/Resources/demo-traffic.json là ví dụ hoàn chỉnh với isDemo: true và các vị trí giả lập. Không chỉ đổi isDemo thành false rồi coi là dữ liệu thực.")
            }
        }.navigationTitle("Định dạng nhập").navigationBarTitleDisplayMode(.inline)
    }
}
