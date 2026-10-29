import SwiftUI
import UIKit

struct NavigationHomeView: View {
    @StateObject private var map = MapModel()
    @State private var showSearch = false
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Group {
                if map.provider == .osm { MapCanvas(model: map) }
                else { AppleMapCanvas(model: map) }
            }.ignoresSafeArea()
            if map.isDemo { DemoRouteOverlay().ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: 0) {
                header
                // Independent, bounded columns keep controls reachable on shorter screens.
                HStack(alignment: .top, spacing: 8) {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 10) {
                            SpeedDial(speed: displayedSpeed, limit: map.isDemo ? 60 : nil)
                            if map.isDemo {
                                WarningSign(symbol: "arrow.turn.up.left", distance: "160 m")
                                WarningSign(symbol: "arrow.turn.up.right", distance: "391 m")
                                WarningSign(symbol: "camera.fill", distance: "398 m", prohibited: false)
                            } else if let error = map.error {
                                Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                                    Label(error, systemImage: "location.slash").font(.caption).multilineTextAlignment(.leading).padding(9)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(width: 150)
                    Spacer(minLength: 0)
                    ScrollView(.vertical) {
                        VStack(spacing: 9) {
                            control("plus", label: "Phóng to") { map.adjustZoom(1) }
                            control("minus", label: "Thu nhỏ") { map.adjustZoom(-1) }
                            control(map.pitch > 0 ? "view.2d" : "view.3d", label: map.pitch > 0 ? "Chuyển bản đồ 2D" : "Chuyển bản đồ 3D") { map.pitch = map.pitch > 0 ? 0 : 45 }
                            control("location.fill", label: "Về vị trí của tôi") { map.locate() }
                            control(map.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", label: map.soundEnabled ? "Tắt âm thanh" : "Bật âm thanh") { map.soundEnabled.toggle() }
                            control("slider.horizontal.3", label: "Cài đặt") { showSettings = true }
                        }.frame(maxWidth: .infinity)
                    }.frame(width: 52)
                }
                .padding(.horizontal, 14).padding(.top, 15)
                .frame(maxHeight: .infinity, alignment: .top)
                HStack {
                    if map.provider == .osm { Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        .font(.system(size: 9, weight: .medium)).foregroundColor(.primary)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(.regularMaterial, in: Capsule()) }
                    Spacer()
                }.padding(.horizontal, 14).padding(.vertical, 8)
                tripBar
            }
        }
        .sheet(isPresented: $showSearch) { SearchPlaceholderView() }
        .sheet(isPresented: $showSettings) { SettingsView(model: map) }
        .onChange(of: scenePhase) { phase in if phase == .background { map.stop() } }
    }
    private var displayedSpeed: Double? {
        if map.isDemo { return 42 }
        guard let fix = map.location, fix.speed >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 10 else { return nil }
        return fix.speed * 3.6
    }
    private var header: some View {
        Button { showSearch = true } label: {
            HStack(spacing: 12) {
                Image(systemName: map.isDemo ? "arrow.turn.up.right" : "magnifyingglass")
                    .font(.system(size: 22, weight: .bold)).frame(width: 28)
                    .foregroundColor(map.isDemo ? Color.vnBlue : Color.vnInk)
                VStack(alignment: .leading, spacing: 2) {
                    if map.isDemo {
                        Text("700 m  Nguyễn Bỉnh Khiêm").font(.system(size: 15, weight: .bold))
                        Text("TUYẾN MÔ PHỎNG · KHÔNG DÙNG ĐỂ LÁI XE").font(.system(size: 9, weight: .heavy)).foregroundColor(.orange)
                    } else {
                        Text("Bạn muốn đi đâu?").font(.system(size: 16, weight: .bold))
                        Text("Tìm địa điểm · Đang phát triển").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
            }.foregroundColor(.primary).padding(.horizontal, 17).frame(minHeight: 58)
             .background(Color.vnSurface)
        }.accessibilityLabel(map.isDemo ? "Chỉ dẫn mô phỏng. Mở tìm kiếm" : "Tìm điểm đến")
         .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }
    private var tripBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "chevron.up").font(.system(size: 14, weight: .bold)).foregroundColor(.secondary).frame(width: 38)
            tripMetric(map.isDemo ? "08:52" : "--:--", caption: "ĐẾN NƠI")
            dot
            tripMetric(map.isDemo ? "15 phút" : "-- phút", caption: "THỜI GIAN", highlighted: true)
            dot
            tripMetric(map.isDemo ? "12,1 km" : "-- km", caption: "QUÃNG ĐƯỜNG")
            Button { showSettings = true } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).frame(width: 38, height: 48) }
                .accessibilityLabel("Tùy chọn")
        }
        .foregroundColor(.primary).padding(.horizontal, 6).padding(.vertical, 9)
        .background(Color.vnSurface.shadow(color: .black.opacity(0.12), radius: 10, y: -2))
    }
    private func tripMetric(_ value: String, caption: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(highlighted ? .vnBlue : .primary).lineLimit(1).minimumScaleFactor(0.75)
            Text(caption).font(.system(size: 8, weight: .bold)).foregroundColor(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
    private var dot: some View { Circle().fill(Color.secondary.opacity(0.35)).frame(width: 3, height: 3).padding(.horizontal, 3) }
    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(.vnBlue)
                .frame(width: 44, height: 44).background(Color.vnSurface, in: RoundedRectangle(cornerRadius: 11))
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
        }.accessibilityLabel(label)
    }
}

private extension Color {
    static let vnBlue = Color(red: 0.02, green: 0.27, blue: 0.78)
    static let vnInk = Color(uiColor: .label)
    static let vnSurface = Color(uiColor: .systemBackground)
}

private struct SpeedDial: View {
    let speed: Double?
    let limit: Int?
    private var speedText: String { speed.map { String(format: "%.0f", $0) } ?? "--" }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(Color(red: 0.02, green: 0.08, blue: 0.22))
                    .overlay(Circle().stroke(Color(red: 0.06, green: 0.22, blue: 0.52), lineWidth: 5))
                Circle().trim(from: 0.11, to: 0.37).stroke(Color.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(90)).padding(8)
                VStack(spacing: 0) {
                    Text(speedText).font(.system(size: 24, weight: .heavy, design: .rounded))
                    Text("km/h").font(.system(size: 8, weight: .bold))
                }.foregroundColor(.white)
            }.frame(width: 76, height: 76)
            if let limit {
                Text("\(limit)").font(.system(size: 17, weight: .black)).foregroundColor(.black)
                    .frame(width: 39, height: 39).background(Circle().fill(.white).overlay(Circle().stroke(.red, lineWidth: 4)))
                    .offset(x: 14, y: 11)
            }
        }.padding(.trailing, limit == nil ? 0 : 13).padding(.bottom, limit == nil ? 0 : 9)
         .shadow(color: .black.opacity(0.20), radius: 4, y: 2)
         .accessibilityElement(children: .ignore)
         .accessibilityLabel("Tốc độ \(speedText) ki lô mét trên giờ. \(limit.map { "Giới hạn mô phỏng \($0)" } ?? "Chưa có dữ liệu giới hạn tốc độ")")
    }
}

private struct WarningSign: View {
    let symbol: String
    let distance: String
    var prohibited = true
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(.white).overlay(Circle().stroke(.red, lineWidth: 4))
                Image(systemName: symbol).font(.system(size: 21, weight: .bold)).foregroundColor(.black)
                if prohibited {
                    Path { p in p.move(to: CGPoint(x: 8, y: 8)); p.addLine(to: CGPoint(x: 38, y: 38)) }
                        .stroke(.red, lineWidth: 3)
                }
            }.frame(width: 46, height: 46)
            Text(distance).font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.black)
                .padding(.horizontal, 4).background(.white, in: Capsule())
        }.shadow(color: .black.opacity(0.18), radius: 3, y: 2)
         .accessibilityLabel("Biển báo mô phỏng, cách \(distance)")
    }
}

/// Không dựa trên GPS hoặc dữ liệu giao thông; chỉ để xem bố cục.
private struct DemoRouteOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in p.move(to: CGPoint(x: w * 0.50, y: h * 0.72)); p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.40)); p.addLine(to: CGPoint(x: w * 0.59, y: h * 0.34)); p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.34)) }
                    .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                Path { p in p.move(to: CGPoint(x: w * 0.50, y: h * 0.72)); p.addLine(to: CGPoint(x: w * 0.50, y: h * 0.40)); p.addLine(to: CGPoint(x: w * 0.59, y: h * 0.34)); p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.34)) }
                    .stroke(Color.vnBlue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                WarningSign(symbol: "arrow.turn.up.right", distance: "", prohibited: true).scaleEffect(0.75).position(x: w * 0.5, y: h * 0.47)
                WarningSign(symbol: "arrow.turn.up.left", distance: "", prohibited: true).scaleEffect(0.75).position(x: w * 0.5, y: h * 0.60)
                Image(systemName: "location.north.fill").font(.system(size: 32, weight: .black)).foregroundColor(.vnBlue)
                    .shadow(color: .white, radius: 2).position(x: w * 0.50, y: h * 0.72)
                Text("MÔ PHỎNG · KHÔNG PHẢI CHỈ DẪN THỰC").font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(.orange, in: Capsule()).position(x: w * 0.50, y: h * 0.30)
            }
        }.accessibilityHidden(true)
    }
}

private struct SearchPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationView {
            Form {
                Section("ĐIỂM ĐẾN") {
                    TextField("Nhập địa điểm hoặc địa chỉ", text: $query).accessibilityLabel("Địa điểm đến")
                    Label("Tìm kiếm và dẫn đường đang được phát triển.", systemImage: "info.circle").font(.footnote).foregroundColor(.secondary)
                }
            }.navigationTitle("Tìm địa điểm").navigationBarTitleDisplayMode(.inline)
             .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
}
private struct SettingsView: View {
    @ObservedObject var model: MapModel
    @StateObject private var updater = TrafficUpdateStore()
    @Environment(\.dismiss) private var dismiss
    private var trafficDataStatus: String {
        guard let url = Bundle.main.url(forResource: "traffic-summary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let counts = json["counts"] as? [String: Int] else {
            return "Chưa có thống kê dữ liệu trong bản cài."
        }
        return "OSM thô: \(counts["traffic_sign", default: 0]) đối tượng biển báo, \(counts["maxspeed", default: 0]) đối tượng có tốc độ, \(counts["speed_camera", default: 0]) camera tốc độ. Các nhóm có thể trùng nhau."
    }
    var body: some View {
        NavigationView {
            Form {
                Section("BẢN ĐỒ") {
                    Picker("Nguồn bản đồ", selection: $model.provider) {
                        ForEach(MapProvider.allCases) { provider in Text(provider.rawValue).tag(provider) }
                    }
                    Text("Cả hai bản đồ hiện cần mạng; MapKit không đảm bảo có bản đồ offline. Chuyển bản đồ chưa hỗ trợ dẫn đường.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("GIAO DIỆN") {
                    Toggle("Xem giao diện mô phỏng", isOn: $model.isDemo)
                    Text("Tuyến, tốc độ, biển báo và thời gian trong chế độ mô phỏng đều là ví dụ, không dùng khi lái xe.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("VỊ TRÍ") {
                    Button("Bật và cập nhật vị trí") { model.locate() }
                    Text("Ứng dụng chỉ truy cập vị trí khi bạn chủ động cấp quyền. Chưa hỗ trợ theo dõi nền.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("DỮ LIỆU OSM TRONG BẢN CÀI") {
                    Text(trafficDataStatus).font(.footnote)
                    if let version = UserDefaults.standard.string(forKey: "trafficDataVersion") { Text("Bản đã tải: \(version)").font(.footnote) }
                    Button(updater.busy ? "Đang cập nhật…" : "Kiểm tra cập nhật dữ liệu") { Task { await updater.update() } }.disabled(updater.busy)
                    Text(updater.status).font(.footnote).foregroundColor(.secondary)
                    Text("Dữ liệu OSM chưa kiểm chứng; chưa kết nối cảnh báo. Không dùng để lái xe.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section("TRẠNG THÁI PHÁT TRIỂN") {
                    Text("Đây là giao diện thử nghiệm. Chưa kết nối tìm kiếm, dẫn đường, cảnh báo thật, dữ liệu offline hay âm thanh.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section { Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!) }
            }.navigationTitle("Cài đặt").navigationBarTitleDisplayMode(.inline)
             .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
}

struct NavigationHomeView_Previews: PreviewProvider {
    static var previews: some View { NavigationHomeView() }
}
