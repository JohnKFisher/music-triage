import SwiftUI

@main
struct MusicTriageApp: App {
    @UIApplicationDelegateAdaptor(MusicTriageApplicationDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            PhoneSceneRoot(model: model)
        }
    }
}

private struct PhoneSceneRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MainScreenView(model: model)
            .task {
                model.start()
                model.handlePhoneScenePhase(scenePhase)
            }
            .onChange(of: scenePhase) { _, newPhase in
                model.handlePhoneScenePhase(newPhase)
            }
    }
}
