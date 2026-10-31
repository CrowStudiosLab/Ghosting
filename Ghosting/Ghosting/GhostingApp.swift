import SwiftUI

@main
struct GhostingApp: App {
    @StateObject private var manager = LocationManager()
    @StateObject private var search = PlaceSearchService()
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .dark
    @AppStorage(OnboardingState.key) private var onboardingDone = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingDone {
                    ContentView()
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
            .environmentObject(manager)
            .environmentObject(search)
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                // Retour sur l'app : le Mac a peut-être coupé la simulation entre-temps
                if phase == .active { Task { await manager.syncWithServer() } }
            }
        }
    }
}
