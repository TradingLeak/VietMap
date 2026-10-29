import SwiftUI
import CoreLocation

/// Xem các tuyến do OSRM trả về trước khi khởi hành.
struct RoutePreviewScreen: View {
    @ObservedObject var routing: NavigationRouteViewModel
    @ObservedObject var engine: NavigationEngine
    @ObservedObject private var locationManager: LocationManager
    let placeName: String?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("vn.distanceUnit") private var unit = "km"
    @State private var latitude: String
    @State private var longitude: String
    @State private var inputError: String?

    init(routing: NavigationRouteViewModel, engine: NavigationEngine, destination: SearchResult?) {
        self.routing = routing; self.engine = engine; self._locationManager = ObservedObject(wrappedValue: .shared); placeName = destination?.displayName
        _latitude = State(initialValue: destination.map { String($0.coordinate.latitude) } ?? "")
        _longitude = State(initialValue: destination.map { String($0.coordinate.longitude) } ?? "")
    }
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("ĐIỂM ĐẾN", systemImage: "mappin.circle.fill").font(.caption.bold()).foregroundStyle(VNTheme.accent)
                        if let placeName { Text("Đã chọn: \(placeName) (có thể sửa tọa độ)").font(.subheadline.weight(.semibold)).foregroundStyle(VNTheme.text) }
                        HStack {
                            TextField("Vĩ độ", text: $latitude).keyboardType(.numbersAndPunctuation).accessibilityLabel("Vĩ độ điểm đến")
                            Divider().frame(height: 25)
                            TextField("Kinh độ", text: $longitude).keyboardType(.numbersAndPunctuation).accessibilityLabel("Kinh độ điểm đến")
                        }.font(.subheadline).padding(12).background(VNTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
                        Text("Xuất phát từ vị trí hiện tại. Tọa độ được gửi đến OSRM demo.").font(.caption).foregroundStyle(VNTheme.secondary)
                        Button(action: calculate) {
                            HStack { Spacer(); if routing.isLoading { ProgressView().tint(VNTheme.onAccent) } else { Text("Tính tuyến đường").fontWeight(.bold) }; Spacer() }
                                .padding(13).foregroundStyle(VNTheme.onAccent).background(VNTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                        }.disabled(routing.isLoading || engine.isNavigating)
                        if let error = inputError ?? routing.errorMessage { Text(error).font(.caption).foregroundStyle(VNTheme.danger) }
                    }.padding(16).background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    if !routing.routes.isEmpty {
                        Text("TUYẾN ĐƯỜNG GỢI Ý").font(.caption.bold()).foregroundStyle(VNTheme.secondary)
                        ForEach(Array(routing.routes.enumerated()), id: \.element.id) { index, route in
                            Button {
                                if !engine.isNavigating { engine.stopNavigation(); routing.select(route) }
                            } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").font(.title3).foregroundStyle(VNTheme.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(index == 0 ? "Tuyến đề xuất" : "Tuyến thay thế \(index)").font(.subheadline.bold()).foregroundStyle(VNTheme.text)
                                        Text("\(NavigationFormat.distance(route.distance, unit: unit)) · \(NavigationFormat.duration(route.duration))").font(.caption).foregroundStyle(VNTheme.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: route.id == routing.selectedRoute?.id ? "checkmark.circle.fill" : "circle").foregroundStyle(VNTheme.accent)
                                }.padding(16).background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            }.disabled(engine.isNavigating || routing.isLoading)
                        }
                        if let route = routing.selectedRoute {
                            Button {
                                engine.startNavigation(route: route)
                                if engine.isNavigating { dismiss() }
                            } label: {
                                Label("Bắt đầu dẫn đường", systemImage: "location.north.fill").fontWeight(.bold).frame(maxWidth: .infinity)
                                    .padding(15).foregroundStyle(VNTheme.onAccent).background(VNTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                            }.disabled(engine.isNavigating || routing.isLoading)
                            if let error = engine.lastError { Text(error).font(.caption).foregroundStyle(VNTheme.danger) }
                            Text("Chỉ dẫn · \(route.steps.count) bước").font(.subheadline.bold()).foregroundStyle(VNTheme.text)
                            ForEach(Array(route.steps.enumerated()), id: \.offset) { _, step in
                                HStack(alignment: .top) {
                                    Image(systemName: "arrow.turn.up.right").foregroundStyle(VNTheme.accent).accessibilityHidden(true)
                                    Text(step.instruction).font(.caption).foregroundStyle(VNTheme.text)
                                    Spacer()
                                    Text(NavigationFormat.distance(step.distance, unit: unit)).font(.caption).foregroundStyle(VNTheme.secondary)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }.padding(16)
            }.background(VNTheme.canvas)
                .onAppear { locationManager.beginRoutePlanning() }
                .onDisappear { locationManager.endRoutePlanning() }
                .onChange(of: locationManager.currentLocation?.timestamp) { _ in
                    if let fix = locationManager.currentLocation, fix.horizontalAccuracy >= 0,
                       fix.horizontalAccuracy <= 100, abs(fix.timestamp.timeIntervalSinceNow) <= 30 { inputError = nil }
                }
                .navigationTitle("Xem trước tuyến").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
    private func calculate() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            inputError = "Ứng dụng chưa được cấp quyền vị trí. Hãy kiểm tra quyền VietNav trong Cài đặt."
            return
        case .notDetermined:
            locationManager.beginRoutePlanning()
            inputError = "Hãy cho phép vị trí để xác định điểm xuất phát."
            return
        default: break
        }
        guard let location = locationManager.currentLocation, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100,
              abs(location.timestamp.timeIntervalSinceNow) <= 30 else {
            locationManager.beginRoutePlanning()
            inputError = "Đang chờ vị trí GPS mới và đủ chính xác. Hãy ra nơi thoáng, bật Vị trí chính xác rồi thử lại."
            return
        }
        let origin = location.coordinate
        guard let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")), let lon = Double(longitude.replacingOccurrences(of: ",", with: ".")),
              lat.isFinite, lon.isFinite, CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else {
            inputError = "Tọa độ điểm đến không hợp lệ."; return
        }
        inputError = nil
        routing.calculate(from: origin, to: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
}
struct RoutePreviewScreen_Previews: PreviewProvider {
    static var previews: some View { RoutePreviewScreen(routing: NavigationRouteViewModel(), engine: NavigationEngine(), destination: nil) }
}
