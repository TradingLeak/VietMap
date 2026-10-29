import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("Lái xe", systemImage: "speedometer") }
            NavigationStack { RoutePlanningView() }.tabItem { Label("Dẫn đường", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            NavigationStack { TripsView() }.tabItem { Label("Hành trình", systemImage: "point.3.connected.trianglepath.dotted") }
            NavigationStack { SettingsView() }.tabItem { Label("Cài đặt", systemImage: "slider.horizontal.3") }
        }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView().interactiveDismissDisabled() }
        .fullScreenCover(isPresented: $model.showHUD) { HUDView() }
        .alert("VietMap", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Đã hiểu", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "location.north.circle.fill").font(.system(size: 66)).foregroundStyle(Palette.accent).padding(.top, 24)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mỗi hành trình,\nan tâm hơn.").font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Chào mừng bạn đến với VietMap").foregroundStyle(.secondary)
                }
                feature("location.fill", "Bạn kiểm soát vị trí", "Chỉ xin quyền khi bạn bắt đầu lái xe. Chạy nền là lựa chọn riêng; không có máy chủ theo dõi của dự án.")
                feature("externaldrive.fill", "Minh bạch về dữ liệu", "Ứng dụng chỉ kèm dữ liệu mô phỏng. Muốn cảnh báo thực tế, hãy nhập dữ liệu có giấy phép và được cập nhật.")
                feature("hand.raised.fill", "An toàn là ưu tiên", "Không thao tác khi xe đang chạy. Tốc độ GPS và cảnh báo chỉ tham khảo; luôn tuân thủ biển báo thực tế.")
                PrimaryButton(title: "Tôi đã hiểu · Tiếp tục", symbol: "checkmark.shield") { model.completeOnboarding() }
                    .accessibilityIdentifier("onboarding.continue")
                Text("Dự án độc lập, không phải sản phẩm chính thức của VIETMAP. Bản đồ và tính tuyến Apple cần Internet và phụ thuộc vùng hỗ trợ. Không có tính năng cao cấp của bên thứ ba bị mở khóa trái phép.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.background(Palette.background)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
