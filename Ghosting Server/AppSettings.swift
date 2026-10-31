import SwiftUI
import Darwin

// MARK: - Configuration du serveur (lue par le réseau ET par les Réglages)

/// `nonisolated` : lu hors MainActor. UserDefaults est thread-safe.
nonisolated enum ServerConfig {
    static let portKey = "server.port"
    static let pythonPathKey = "server.pythonPath"
    static let udidKey = "server.udid"
    static let tokenKey = "server.token"
    static let defaultPort = 5001

    /// Python du venv utilisé par défaut tant qu'aucun chemin n'est saisi dans les Réglages.
    static let defaultPythonPath = "/Users/edouard/Code/APPS/Ghosting/GhostingServer/venv/bin/python3"

    /// Interface d'écoute de server.py : 0.0.0.0 pour que l'app iPhone le joigne sur le Wi-Fi.
    static let listenHost = "0.0.0.0"
    /// L'app parle à son propre serveur en local.
    static let host = "127.0.0.1"

    /// Port enregistré, ou le port par défaut s'il est absent / hors limites.
    static var port: Int {
        let stored = UserDefaults.standard.integer(forKey: portKey)
        return isValid(port: stored) ? stored : defaultPort
    }

    static func isValid(port: Int) -> Bool { (1...65535).contains(port) }

    static var baseURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url
    }

    /// Chemin Python choisi par l'utilisateur (vide = venv par défaut, puis détection automatique).
    static var pythonPath: String { string(pythonPathKey) }
    /// UDID de l'iPhone (optionnel : utile si plusieurs appareils sont branchés).
    static var udid: String { string(udidKey) }
    /// Jeton optionnel (header X-Token). Vide = pas d'authentification, comme l'app iPhone par défaut.
    static var token: String { string(tokenKey) }

    private static func string(_ key: String) -> String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var unreachableError: ServerError {
        ServerError(message: "Le serveur Ghosting ne répond pas (\(host):\(port)). Vérifie son état dans les réglages.")
    }
}

// MARK: - Adresse du Mac sur le réseau local (à saisir dans l'app iPhone)

nonisolated enum LocalNetwork {
    static func ipv4Address() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var fallback: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = pointer.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buffer)
            guard !ip.hasPrefix("169.254") else { continue }   // adresse auto-attribuée : pas de vrai réseau

            if name == "en0" { return ip }
            fallback = fallback ?? ip
        }
        return fallback
    }
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

    /// nil = suit le réglage du Mac.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
