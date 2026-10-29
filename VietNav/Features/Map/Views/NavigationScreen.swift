import SwiftUI
import UIKit

struct NavigationScreen: View {
    @StateObject private var map = MapViewModel()
    @StateObject private var routing = NavigationRouteViewModel()
    @StateObject private var navigation = NavigationEngine()
    @StateObject private var speed = SpeedWarningEngine()
    @ObservedObject private var battery = BatteryOptimizer.shared
    @State private var sheet: Sheet?
    @State private var selectedPlace: SearchResult?
    @State private var openRouteAfterSearch = false
    @State private var confirmStop = false
    @State private var lastHapticStep: Int?
    @State private var visible = false
    @AppStorage("vn.mapAppearance") private var appearance = "system"
    @AppStorage("vn.haptics") private var haptics = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Sheet: String, Identifiable { case search, route, settings, report; var id: String { rawValue } }
    private var preferredScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
    private var nextStep: RouteStep? {
        guard let route = navigation.currentRoute, route.steps.indices.contains(navigation.currentStepIndex + 1) else { return nil }
        return route.steps[navigation.currentStepIndex + 1]
    }

    var body: some View {
        ZStack {
            MapViewRepresentable(viewModel: map, route: navigation.currentRoute ?? routing.selectedRoute, warnings: speed.upcomingWarnings, fitRoute: !navigation.isNavigating).ignoresSafeArea()
            VStack(spacing: 10) {
                if navigation.isNavigating, let step = navigation.currentStep {
                    TurnInstructionBanner(step: step, distance: navigation.distanceToNextManeuver, nextStep: nextStep)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    searchBar
                }
                if navigation.isRerouting {
                    statusChip("Đang tính lại lộ trình…", icon: "arrow.triangle.2.circlepath")
                } else if navigation.isOffRoute {
                    statusChip("Có thể đã lệch tuyến", icon: "exclamationmark.triangle.fill")
                } else if navigation.isArrived {
                    statusChip("Bạn đã đến nơi", icon: "checkmark.circle.fill")
                }
                if let error = navigation.lastError ?? map.locationError ?? speed.lastError {
                    HStack {
                        Text(error).font(.caption).lineLimit(3)
                        if map.authorization == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                            Button("Cài đặt") { openURL(url) }.font(.caption.bold())
                        }
                    }.padding(10).foregroundStyle(VNTheme.text).background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack(alignment: .top) {
                    if navigation.isNavigating, let step = navigation.currentStep, !step.lanes.isEmpty { laneStrip(step.lanes) }
                    VStack(alignment: .leading, spacing: 8) {
                        SpeedHUDView(currentSpeed: speed.hasFreshLocation && speed.hasSpeedMeasurement ? speed.currentSpeed : nil,
                                     speedLimit: speed.currentSpeedLimit, isOverSpeeding: speed.isOverSpeeding)
                        ForEach(Array(speed.upcomingWarnings.prefix(3))) { warning in
                            UpcomingWarningCard(warning: warning)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        VStack(spacing: 1) {
                            mapButton("plus", label: "Phóng to") { map.setZoom(map.zoomLevel + 1) }
                            Rectangle().fill(VNTheme.border).frame(width: 27, height: 1)
                            mapButton("minus", label: "Thu nhỏ") { map.setZoom(map.zoomLevel - 1) }
                        }.background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: VNTheme.shadow.opacity(0.12), radius: 6, y: 3)
                        mapButton("location.fill", label: "Về vị trí của tôi") { map.centerOnUser() }
                            .background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        Button(map.pitch > 0 ? "2D" : "3D") { map.setPitch(map.pitch > 0 ? 0 : 60) }
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(VNTheme.text).frame(width: 44, height: 44)
                            .background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel(map.pitch > 0 ? "Chuyển sang bản đồ 2D" : "Chuyển sang bản đồ 3D")
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(VNTheme.text)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(VNTheme.surface.opacity(0.92), in: Capsule())
                    Spacer()
                    if navigation.isNavigating {
                        Button { sheet = .report } label: {
                            Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(VNTheme.accent)
                                .frame(width: 40, height: 40).background(VNTheme.surface, in: Circle())
                        }.accessibilityLabel("Báo cáo giao thông")
                        Button { sheet = .settings } label: {
                            Image(systemName: "slider.horizontal.3").foregroundStyle(VNTheme.text)
                                .frame(width: 40, height: 40).background(VNTheme.surface, in: Circle())
                        }.accessibilityLabel("Cài đặt")
                    }
                }
                if navigation.isNavigating {
                    NavigationBottomBar(duration: navigation.durationRemaining, distance: navigation.distanceRemaining,
                                        eta: navigation.estimatedArrivalTime, progress: navigation.progressFraction,
                                        onStop: { confirmStop = true })
                } else if navigation.isArrived {
                    Button("Kết thúc hành trình") { navigation.stopNavigation(); routing.clear(); map.centerOnUser() }
                        .font(.headline).foregroundStyle(VNTheme.onAccent).frame(maxWidth: .infinity).padding(16)
                        .background(VNTheme.accent, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    readyCard
                }
            }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
        }
        .preferredColorScheme(preferredScheme)
        .animation(reduceMotion || battery.reducedRendering ? nil : .easeInOut(duration: 0.2), value: navigation.isNavigating)
        .onAppear { visible = true; map.start(); if scenePhase == .active || navigation.isNavigating { speed.start() } }
        .onDisappear { visible = false; map.stop(); routing.cancel(); if !navigation.isNavigating { speed.stop() } }
        .onChange(of: navigation.isNavigating) { navigating in
            if navigating || (visible && scenePhase == .active) { speed.start() } else { speed.stop() }
            if navigating { map.setZoom(17); map.centerOnUser() }
        }
        .onChange(of: scenePhase) { phase in
            if navigation.isNavigating || (visible && phase == .active) { speed.start() } else { speed.stop() }
        }
        .onChange(of: speed.isOverSpeeding) { over in
            if over && haptics && scenePhase == .active { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        .onChange(of: navigation.distanceToNextManeuver) { distance in
            guard haptics, scenePhase == .active, navigation.isNavigating, distance > 0, distance <= 100,
                  let step = navigation.currentStep, step.maneuver != .arrive, step.maneuver != .depart,
                  lastHapticStep != navigation.currentStepIndex else { return }
            lastHapticStep = navigation.currentStepIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onChange(of: navigation.currentRoute?.id) { _ in lastHapticStep = nil }
        .confirmationDialog("Dừng dẫn đường?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Dừng dẫn đường", role: .destructive) { navigation.stopNavigation(); routing.clear(); map.centerOnUser() }
            Button("Tiếp tục", role: .cancel) {}
        }
        .sheet(item: $sheet, onDismiss: {
            if openRouteAfterSearch { openRouteAfterSearch = false; sheet = .route }
        }) { selected in
            switch selected {
            case .search:
                SearchScreen { place in
                    selectedPlace = place; routing.clear(); openRouteAfterSearch = true; sheet = nil
                }
            case .route:
                RoutePreviewScreen(routing: routing, engine: navigation, destination: selectedPlace)
                    .presentationDetents([.medium, .large])
            case .settings: SettingsScreen(isNavigating: navigation.isNavigating)
            case .report: ReportScreen(location: map.currentLocation)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Button { if navigation.isArrived { navigation.stopNavigation() }; sheet = .search } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(VNTheme.accent)
                    Text("Tìm địa điểm, địa chỉ...").foregroundStyle(VNTheme.secondary).font(.subheadline)
                    Spacer(minLength: 0)
                }.padding(.leading, 16).frame(height: 52).contentShape(Rectangle())
            }.accessibilityLabel("Tìm địa điểm")
            Button { sheet = .settings } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VNTheme.text).frame(width: 46, height: 52)
            }.accessibilityLabel("Cài đặt")
        }
        .background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: VNTheme.shadow.opacity(0.15), radius: 10, y: 4)
    }
    private var readyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.north.circle.fill").font(.system(size: 36)).foregroundStyle(VNTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sẵn sàng lên đường").font(.subheadline.bold()).foregroundStyle(VNTheme.text)
                Text("Tìm điểm đến để bắt đầu").font(.caption).foregroundStyle(VNTheme.secondary)
            }
            Spacer(minLength: 0)
            Button { sheet = .report } label: {
                Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 18))
                    .foregroundStyle(VNTheme.accent).frame(width: 44, height: 44).background(VNTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityLabel("Báo cáo giao thông")
            Button { selectedPlace = nil; sheet = .route } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.system(size: 18))
                    .foregroundStyle(VNTheme.onAccent).frame(width: 44, height: 44).background(VNTheme.accent, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityLabel("Nhập tọa độ và tính tuyến")
        }.padding(14).background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: VNTheme.shadow.opacity(0.14), radius: 10, y: 4)
    }
    private func mapButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(VNTheme.text).frame(width: 44, height: 44) }
            .accessibilityLabel(label)
    }
    private func statusChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.caption.bold()).foregroundStyle(VNTheme.text)
            .padding(.horizontal, 12).padding(.vertical, 8).background(VNTheme.surface, in: Capsule())
    }
    private func laneStrip(_ lanes: [LaneGuidance]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                VStack(spacing: 2) {
                    Image(systemName: laneSymbol(lane)).font(.system(size: 15, weight: .bold))
                    if lane.valid == true { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                }.foregroundStyle(lane.valid == true ? VNTheme.accent : VNTheme.secondary)
                    .accessibilityLabel("Làn \(lane.indications.joined(separator: ", "))\(lane.valid == true ? ", được gợi ý" : "")")
            }
        }.padding(10).background(VNTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func laneSymbol(_ lane: LaneGuidance) -> String {
        if lane.indications.contains(where: { $0.contains("left") }) { return "arrow.turn.up.left" }
        if lane.indications.contains(where: { $0.contains("right") }) { return "arrow.turn.up.right" }
        if lane.indications.contains("reverse") { return "arrow.uturn.down" }
        return "arrow.up"
    }
}

struct NavigationScreen_Previews: PreviewProvider {
    static var previews: some View { NavigationScreen().previewDisplayName("Bản đồ") }
}
