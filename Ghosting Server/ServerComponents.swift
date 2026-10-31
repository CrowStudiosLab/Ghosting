import SwiftUI
import AppKit

/// Pastille « état du serveur » (Réglages, introduction).
struct ServerStateBadge: View {
    let state: ServerProcess.State

    var body: some View {
        let (text, color): (String, Color) = switch state {
        case .stopped: ("Arrêté", .gray)
        case .starting: ("Démarrage…", Theme.accent)
        case .running: ("En marche", Theme.live)
        case .stopping: ("Arrêt…", .gray)
        case .failed: ("Erreur", Theme.danger)
        }
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color, radius: 4)
            Text(text).font(.footnote.weight(.semibold))
        }
        .contentTransition(.opacity)
    }
}

/// Sélecteur de fichier pour l'interpréteur Python.
enum PythonPicker {
    @MainActor
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choisis l'exécutable Python 3 (par exemple « bin/python3 » d'un environnement virtuel)."
        panel.prompt = "Choisir"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
