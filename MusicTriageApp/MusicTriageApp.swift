import SwiftUI

@main
struct MusicTriageApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainScreenView(model: model)
                .task {
                    model.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    model.handleScenePhase(newPhase)
                }
        }
    }
}
