import SwiftUI

// MARK: - Configuration du serveur (lue par le réseau ET par l'écran Réglages)

/// `nonisolated` : lu depuis `MacServerSimulator` (hors MainActor). UserDefaults est thread-safe.
nonisolated enum ServerConfig {
    static let hostKey = "server.host"
    static let portKey = "server.port"
    static let defaultHost = "192.168.1.19"
    static let defaultPort = 5001

    /// Hôte nettoyé : espaces, « http:// » et « / » finaux retirés si l'utilisateur les a saisis.
    static var host: String {
        var value = (UserDefaults.standard.string(forKey: hostKey) ?? defaultHost)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://"] where value.lowercased().hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// Port enregistré, ou le port par défaut s'il est absent / hors limites.
    static var port: Int {
        let stored = UserDefaults.standard.integer(forKey: portKey)
        return isValid(port: stored) ? stored : defaultPort
    }

    static func isValid(port: Int) -> Bool { (1...65535).contains(port) }

    static var baseURL: URL? {
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url
    }

    static var invalidAddressError: ServerError {
        ServerError(message: "Adresse du PC invalide. Vérifie l'IP dans les réglages.")
    }

    static var unreachableError: ServerError {
        ServerError(message: "Impossible de joindre le PC (\(host):\(port)). Vérifie l'IP, le port et que le serveur tourne.")
    }
}

// MARK: - Langue

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "app.language"

    case french = "fr"
    case english = "en"

    var id: String { rawValue }
    var flag: String { self == .french ? "🇫🇷" : "🇬🇧" }
    var label: String { self == .french ? "Français" : "English" }
}

// MARK: - Apparence

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "app.appearance"

    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    /// nil = suit le réglage de l'iPhone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Introduction (premier lancement)

enum OnboardingState {
    /// Passe à `true` quand l'introduction est terminée ou passée.
    static let key = "onboarding.completed"
}
