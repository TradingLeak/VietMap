import Foundation

/// Nhập seed do người dùng chọn. Dữ liệu là tham khảo, không phải dữ liệu đã xác minh.
@MainActor
final class TrafficDataImport: ObservableObject {
    @Published private(set) var importing = false
    @Published var message: String?
    func install(_ source: URL) {
        guard !importing else { return }
        importing = true; message = nil
        let accessed = source.startAccessingSecurityScopedResource()
        Task {
            defer { if accessed { source.stopAccessingSecurityScopedResource() }; importing = false }
            do {
                let installed = try await Task.detached(priority: .utility) {
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
                    defer { try? FileManager.default.removeItem(at: temp) }
                    try FileManager.default.copyItem(at: source, to: temp)
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                    return try TrafficDatabase.shared.installTrafficUpdate(from: temp.path, version: formatter.string(from: Date()))
                }.value
                message = installed ? "Đã nhập dữ liệu OSM. Biển báo chỉ để tham khảo và có thể thiếu hoặc sai." : "Không có phiên bản mới hơn để nhập."
            } catch { message = "Không thể nhập dữ liệu giao thông: \(error.localizedDescription)" }
        }
    }
}
