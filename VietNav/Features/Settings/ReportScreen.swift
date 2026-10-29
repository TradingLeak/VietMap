import SwiftUI
import CoreLocation

struct ReportScreen: View {
    let location: CLLocation?
    @Environment(\.dismiss) private var dismiss
    @State private var type: NodeType = .speedCamera
    @State private var detail = ""
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?
    private let choices: [(NodeType, String)] = [(.incident, "Sự cố giao thông"), (.speedCamera, "Camera tốc độ"), (.redLightCamera, "Camera đèn đỏ"), (.tollBooth, "Trạm thu phí"), (.railwayCrossing, "Giao cắt đường sắt"), (.speedLimit, "Biển tốc độ"), (.noOvertaking, "Cấm vượt")]
    var body: some View {
        NavigationView {
            Form {
                Section("Loại báo cáo") {
                    Picker("Loại", selection: $type) { ForEach(choices, id: \.0) { choice in Text(choice.1).tag(choice.0) } }
                    TextField("Ghi chú (không bắt buộc)", text: $detail, axis: .vertical).lineLimit(3...5)
                }
                Section("Vị trí") {
                    if let location {
                        Text(String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)).font(.subheadline.monospacedDigit())
                    } else { Text("Chưa có vị trí GPS.").foregroundStyle(VNTheme.secondary) }
                    Text("Báo cáo chỉ lưu trên thiết bị, chưa được gửi hoặc xác minh và không tự trở thành cảnh báo.").font(.caption).foregroundStyle(VNTheme.secondary)
                }
                Section {
                    Button(saved ? "Đã lưu báo cáo" : "Lưu báo cáo") { save() }.disabled(saving || saved || location == nil)
                    if saving { ProgressView() }
                    if let error { Text(error).font(.caption).foregroundStyle(VNTheme.danger) }
                }
            }.navigationTitle("Báo cáo giao thông").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
    private func save() {
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
              abs(location.timestamp.timeIntervalSinceNow) <= 30, CLLocationCoordinate2DIsValid(location.coordinate) else {
            error = "Vị trí cũ hoặc thiếu chính xác. Vui lòng chờ GPS cập nhật."; return
        }
        let report = UserReport(type: type, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                description: detail.trimmingCharacters(in: .whitespacesAndNewlines), reportedAt: Int64(Date().timeIntervalSince1970))
        saving = true; error = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try TrafficDatabase.shared.saveUserReport(report) }.value
                saved = true; saving = false
            } catch { self.error = "Không thể lưu báo cáo: \(error.localizedDescription)"; saving = false }
        }
    }
}
struct ReportScreen_Previews: PreviewProvider { static var previews: some View { ReportScreen(location: nil) } }
