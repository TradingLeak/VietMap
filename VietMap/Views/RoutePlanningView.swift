import SwiftUI
import MapKit
import VietMapCore

struct RoutePlanningView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: NavigationService
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Đi đâu hôm nay?").font(.largeTitle.bold())
                Text("Tìm điểm đến, chọn tuyến và để VietMap đồng hành.").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.accent)
                    TextField("Địa điểm hoặc địa chỉ", text: $query).submitLabel(.search).focused($searchFocused)
                        .onSubmit { search() }.accessibilityIdentifier("navigation.search")
                    if navigation.isSearching { ProgressView() }
                    else { Button(action: search) { Image(systemName: "arrow.right.circle.fill").font(.title2) }.accessibilityLabel("Tìm địa điểm") }
                }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 17)).disabled(!model.canEdit)
                if !model.canEdit { InformationBanner(text: "Dừng xe an toàn trước khi tìm hoặc đổi điểm đến.", symbol: "hand.raised.fill") }
                if model.mode != .live {
                    InformationBanner(text: "Bật phiên lái xe để lấy GPS thật trước khi tính tuyến. Mô phỏng không được dùng làm vị trí dẫn đường.", symbol: "location.fill")
                    if model.mode == .idle {
                        Button("Bật GPS · Bắt đầu lái xe") { Task { await model.startDriving() } }.font(.subheadline.bold()).disabled(model.isBusy || !model.isReady)
                    }
                }
                if let error = navigation.errorMessage { InformationBanner(text: error, symbol: "wifi.exclamationmark") }
                if navigation.isCalculating { HStack { ProgressView(); Text("Đang tính tuyến ô tô…").font(.subheadline) }.padding() }
                ForEach(Array(navigation.results.enumerated()), id: \.offset) { _, item in
                    Button { select(item) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.accent).font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name ?? "Điểm đến").font(.headline).foregroundStyle(.primary)
                                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.panel()
                    }.buttonStyle(.plain).disabled(!model.canEdit || navigation.isCalculating)
                }
                if !navigation.routes.isEmpty {
                    MapPreview(showRoutePreview: true).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 24))
                    if let name = navigation.destination?.name { Text(name).font(.title3.bold()) }
                    if navigation.activeRoute != nil {
                        ActiveRouteCard()
                        Button("Kết thúc dẫn đường", role: .destructive) { navigation.stop() }.font(.subheadline.bold())
                    } else {
                        ForEach(Array(navigation.routes.enumerated()), id: \.offset) { index, route in
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text(index == 0 ? "Tuyến đề xuất" : "Tuyến thay thế \(index)").font(.caption.bold()).foregroundStyle(Palette.accent)
                                    Spacer(); Text(DisplayFormat.distance(route.distance)).font(.headline)
                                }
                                Text(route.name).font(.subheadline)
                                HStack {
                                    Label(DisplayFormat.duration(route.expectedTravelTime), systemImage: "clock")
                                    Spacer()
                                    Button("Bắt đầu dẫn đường") { start(route) }.fontWeight(.bold)
                                        .disabled(model.mode != .live || !model.snapshot.isReliable || !model.canEdit)
                                }.font(.subheadline)
                            }.panel()
                        }
                    }
                    if let url = appleMapsURL {
                        Button { openURL(url) } label: { Label("Mở điểm đến trong Apple Maps", systemImage: "arrow.up.forward.app") }.font(.subheadline)
                            .disabled(!model.canEdit)
                    }
                    Button("Xóa tuyến đã tìm") { navigation.stop(); navigation.clearPreview() }.font(.caption).foregroundStyle(.secondary).disabled(!model.canEdit)
                } else if navigation.results.isEmpty, !navigation.isSearching {
                    VStack(spacing: 16) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 52)).foregroundStyle(Palette.accent.opacity(0.65))
                        Text("Hành trình bắt đầu từ một điểm đến").font(.headline).multilineTextAlignment(.center)
                        Text("Tính tuyến, tuyến thay thế, tiến độ và tính lại khi lệch đường. Khả năng dẫn đường phụ thuộc dữ liệu Apple Maps tại khu vực của bạn.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                Text("Nguồn: Apple Maps. Cần kết nối mạng cho tìm kiếm và tính tuyến; dữ liệu cảnh báo ngoại tuyến được quản lý riêng. Thông tin tuyến không được dùng để suy đoán tốc độ cho phép.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("Dẫn đường").navigationBarTitleDisplayMode(.inline)
    }

    private func search() {
        guard model.canEdit else { return }
        searchFocused = false
        Task { await navigation.search(query, around: model.mode == .live ? model.latestFix?.coordinate : nil) }
    }

    private func select(_ item: MKMapItem) {
        guard model.canEdit, model.mode == .live, let fix = model.latestFix, fix.isUsable(at: Date()) else {
            model.errorMessage = "Cần vị trí GPS thật và mới. Hãy bắt đầu lái xe, chờ GPS rồi chọn lại điểm đến."
            return
        }
        Task { await navigation.calculate(to: item, from: fix.coordinate) }
    }

    private func start(_ route: MKRoute) {
        guard model.mode == .live, model.snapshot.isReliable, model.canEdit else { return }
        navigation.start(route)
        model.speech.enqueue([Announcement(text: "Bắt đầu dẫn đường. Hãy tuân thủ biển báo thực tế.")])
    }

    private var appleMapsURL: URL? {
        guard let coordinate = navigation.destination?.placemark.coordinate else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d")
    }
}

struct ActiveRouteCard: View {
    @EnvironmentObject private var navigation: NavigationService
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(navigation.progress?.hasArrived == true ? "Đã đến gần điểm đến" : "Đang dẫn đường", systemImage: "arrow.triangle.turn.up.right.diamond.fill").font(.headline).foregroundStyle(Palette.mint)
            Text(navigation.progress?.nextInstruction ?? "Tiếp tục theo tuyến đã chọn").font(.title3.bold())
            if let distance = navigation.progress?.distanceToInstruction { Text("Sau \(DisplayFormat.distance(distance))").font(.subheadline).foregroundStyle(.secondary) }
            HStack {
                StatLabel(value: DisplayFormat.distance(navigation.progress?.remainingMetres ?? navigation.activeRoute?.distance ?? 0), title: "Còn lại")
                StatLabel(value: remainingTime, title: "Thời gian ước tính")
            }
            if navigation.progress?.isOffRoute == true { Text("Đã lệch tuyến. Đang thử tính lại, tối đa một lần mỗi 30 giây.").font(.caption).foregroundStyle(Palette.amber) }
        }.panel()
    }

    private var remainingTime: String {
        guard let route = navigation.activeRoute, route.distance > 0 else { return "– –" }
        let ratio = min(1, (navigation.progress?.remainingMetres ?? route.distance) / route.distance)
        return DisplayFormat.duration(route.expectedTravelTime * ratio)
    }
}
