import SwiftUI
import VietNavCore

struct AppCoordinator: View {
    @State private var databaseError: String?
    var body: some View {
        MapContainerView()
            .task {
                do { try await TrafficDatabase.shared.importInitialDataIfNeeded() }
                catch { databaseError = error.localizedDescription }
            }
            .alert("Không thể mở dữ liệu giao thông", isPresented: Binding(
                get: { databaseError != nil }, set: { if !$0 { databaseError = nil } }
            )) {
                Button("Đóng", role: .cancel) { databaseError = nil }
            } message: { Text(databaseError ?? "") }
    }
}
