import SwiftUI

@main
struct VoilaxaChatApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        model.lockImmediately()
                    }
                }
        }
    }
}
