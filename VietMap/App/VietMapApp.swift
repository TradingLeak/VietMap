import SwiftUI

@main
struct VietMapApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.location)
                .environmentObject(model.navigation)
                .environmentObject(model.speech)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .tint(Palette.accent)
                .task { await model.bootstrap() }
                .onChange(of: scenePhase) { _, phase in model.sceneChanged(isActive: phase == .active) }
        }
    }
}
