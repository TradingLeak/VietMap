import SwiftUI
import MapKit
import VietMapCore

struct TripsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if model.trips.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có hành trình", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Bắt đầu lái xe hoặc chạy mô phỏng. Khi kết thúc, nhật ký được lưu riêng trên thiết bị và có thể xuất GPX / CSV.")
                }
            } else {
                List {
                    Section {
                        ForEach(model.trips) { trip in
                            NavigationLink(value: trip.id) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(trip.startedAt, format: .dateTime.day().month().year()).font(.headline)
                                        Spacer()
                                        if trip.isDemo { Text("MÔ PHỎNG").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.amber) }
                                    }
                                    HStack(spacing: 14) {
                                        Label(DisplayFormat.distance(trip.distanceMetres), systemImage: "road.lanes")
                                        Label(DisplayFormat.duration(trip.duration), systemImage: "clock")
                                    }.font(.caption).foregroundStyle(.secondary)
                                    if trip.wasInterrupted { Label("Đã khôi phục sau gián đoạn", systemImage: "arrow.clockwise").font(.caption2).foregroundStyle(Palette.amber) }
                                }.padding(.vertical, 8)
                            }
                        }.onDelete { offsets in
                            let ids = offsets.compactMap { model.trips.indices.contains($0) ? model.trips[$0].id : nil }
                            Task { for id in ids { await model.deleteTrip(id) } }
                        }.deleteDisabled(!model.canManageData)
                    } footer: { Text("Lưu tự động mỗi 15 giây. Không nối quãng đường qua khoảng mất GPS trên 15 giây. Vuốt để xóa khi đã kết thúc lái xe.") }
                }
            }
        }
        .background(Palette.background).navigationTitle("Hành trình")
        .navigationDestination(for: UUID.self) { TripDetailView(id: $0) }
    }
}

struct ShareFile: Identifiable { let id = UUID(); let url: URL }

struct TripDetailView: View {
    let id: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var trip: Trip?
    @State private var segments: [[CLLocationCoordinate2D]] = []
    @State private var shareFile: ShareFile?
    @State private var confirmDelete = false
    @State private var exporting = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let trip {
                VStack(alignment: .leading, spacing: 20) {
                    if trip.isDemo { InformationBanner(text: "Đây là nhật ký mô phỏng, không phải hành trình thực.", symbol: "play.circle.fill") }
                    if trip.wasInterrupted { InformationBanner(text: "Hành trình được khôi phục đến điểm lưu tự động cuối cùng. Phần chưa kịp lưu có thể bị thiếu.") }
                    Map {
                        ForEach(segments.indices, id: \.self) { index in MapPolyline(coordinates: segments[index]).stroke(Palette.accent, lineWidth: 5) }
                        if let first = trip.points.first { Marker("Bắt đầu", coordinate: first.coordinate.clCoordinate).tint(Palette.mint) }
                        if let last = trip.points.last { Marker("Kết thúc", coordinate: last.coordinate.clCoordinate).tint(Palette.accent) }
                    }.frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 20) {
                        Text(trip.startedAt, format: .dateTime.day().month().year().hour().minute()).font(.headline)
                        HStack {
                            StatLabel(value: DisplayFormat.distance(trip.distanceMetres), title: "Quãng đường")
                            StatLabel(value: DisplayFormat.duration(trip.duration), title: "Thời gian")
                        }
                        HStack {
                            StatLabel(value: "\(Int(trip.maximumSpeedKmh)) km/h", title: "Tốc độ cao nhất")
                            StatLabel(value: "\(Int(trip.averageSpeedKmh)) km/h", title: "Trung bình cả thời gian dừng")
                        }
                        Text("\(trip.points.count) điểm GPS · lưu trên thiết bị").font(.caption).foregroundStyle(.secondary)
                    }.panel()
                    Text("Xuất dữ liệu").font(.headline)
                    InformationBanner(text: "Tệp xuất có vị trí và thời gian di chuyển. Chỉ chia sẻ với người hoặc dịch vụ bạn tin cậy.", symbol: "lock.shield.fill", color: Palette.mint)
                    HStack(spacing: 12) {
                        Button { export(gpx: true) } label: { Label("GPX", systemImage: "map").frame(maxWidth: .infinity).padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)) }
                        Button { export(gpx: false) } label: { Label("CSV", systemImage: "tablecells").frame(maxWidth: .infinity).padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)) }
                    }.font(.headline).disabled(exporting)
                    if exporting { ProgressView("Đang tạo tệp…") }
                    Button("Xóa hành trình", role: .destructive) { confirmDelete = true }.disabled(!model.canManageData)
                }.padding(20)
            } else if failed {
                ContentUnavailableView("Không đọc được hành trình", systemImage: "exclamationmark.triangle", description: Text("Tệp có thể không còn tồn tại. Các hành trình khác không bị thay đổi."))
            } else { ProgressView("Đang đọc hành trình…").padding(40) }
        }
        .background(Palette.background).navigationTitle("Chi tiết hành trình").navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let value = try await model.loadTrip(id)
                segments = pathSegments(value)
                trip = value
            } catch { failed = true }
        }
        .sheet(item: $shareFile) { ShareSheet(url: $0.url) }
        .confirmationDialog("Xóa vĩnh viễn hành trình này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xóa hành trình", role: .destructive) { Task { await model.deleteTrip(id); if !model.trips.contains(where: { $0.id == id }) { dismiss() } } }
        }
    }

    private func export(gpx: Bool) {
        exporting = true
        Task {
            defer { exporting = false }
            do { shareFile = ShareFile(url: try await model.exportTrip(id, gpx: gpx)) }
            catch { model.errorMessage = "Không xuất được tệp: \(error.localizedDescription)" }
        }
    }

    private func pathSegments(_ trip: Trip) -> [[CLLocationCoordinate2D]] {
        var groups: [[TripPoint]] = []
        for point in trip.points {
            if let previous = groups.last?.last, point.timestamp.timeIntervalSince(previous.timestamp) <= 15 { groups[groups.count - 1].append(point) }
            else { groups.append([point]) }
        }
        let step = max(1, trip.points.count / 3_000)
        return groups.filter { $0.count >= 2 }.map { group in
            var reduced = stride(from: 0, to: group.count, by: step).map { group[$0].coordinate.clCoordinate }
            if let last = group.last { reduced.append(last.coordinate.clCoordinate) }
            return reduced
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
