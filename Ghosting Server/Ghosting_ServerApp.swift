import SwiftUI
import AppKit

@main
struct GhostingMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var server = ServerProcess.shared
    @StateObject private var monitor = DeviceMonitor()
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .dark
    @AppStorage(OnboardingState.key) private var onboardingDone = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingDone {
                    ContentView().transition(.opacity)
                } else {
                    MacOnboardingView().transition(.opacity)
                }
            }
            .environmentObject(server)
            .environmentObject(monitor)
            .preferredColorScheme(appearance.colorScheme)
            .task { monitor.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Une seule fenêtre : le serveur est unique
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - Cycle de vie : lance le serveur au démarrage, l'arrête proprement à la fermeture

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Premier lancement : l'introduction configure Python, puis démarre le serveur elle-même
        guard UserDefaults.standard.bool(forKey: OnboardingState.key) else { return }
        Task { await ServerProcess.shared.start() }
    }

    /// Fermer la fenêtre quitte l'app (et donc arrête le serveur).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Cmd+Q, menu Quitter, déconnexion… : on attend la fin de l'arrêt propre avant de fermer.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let server = ServerProcess.shared
        guard server.state != .stopped else { return .terminateNow }

        Task {
            await server.stop(timeout: 6)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
