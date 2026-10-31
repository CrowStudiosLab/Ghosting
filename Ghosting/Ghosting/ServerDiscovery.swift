import SwiftUI
import Network
import Combine

/// Un Mac Ghosting trouvé sur le réseau local.
nonisolated struct DiscoveredServer: Identifiable, Equatable, Sendable {
    let name: String
    let host: String
    let port: Int
    var id: String { "\(name)|\(host)|\(port)" }
}

/// Cherche les serveurs Ghosting annoncés en Bonjour (`_ghosting._tcp`) et retrouve leur adresse IPv4.
@MainActor
final class ServerDiscovery: ObservableObject {
    nonisolated static let serviceType = "_ghosting._tcp"

    @Published private(set) var servers: [DiscoveredServer] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?
    private var found: [NWEndpoint: DiscoveredServer] = [:]
    private var resolutions: [NWEndpoint: Task<Void, Never>] = [:]

    // MARK: Recherche

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                    self?.browser = nil
                default:
                    break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = Set(results.map(\.endpoint))
            Task { @MainActor [weak self] in self?.update(endpoints) }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolutions.values.forEach { $0.cancel() }
        resolutions = [:]
        found = [:]
        servers = []
        isSearching = false
    }

    // MARK: Interne

    private func update(_ endpoints: Set<NWEndpoint>) {
        // Services disparus
        for gone in Set(found.keys).subtracting(endpoints) { found[gone] = nil }
        for (endpoint, task) in resolutions where !endpoints.contains(endpoint) {
            task.cancel()
            resolutions[endpoint] = nil
        }
        // Nouveaux services : on retrouve leur IP
        for endpoint in endpoints where resolutions[endpoint] == nil && found[endpoint] == nil {
            resolutions[endpoint] = Task { [weak self] in
                let server = await Self.resolve(endpoint)
                guard !Task.isCancelled, let self else { return }
                if let server {
                    self.found[endpoint] = server
                } else {
                    self.resolutions[endpoint] = nil   // on réessaiera au prochain changement
                }
                self.publishList()
            }
        }
        publishList()
    }

    private func publishList() {
        servers = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Ouvre une connexion TCP vers le service (IPv4) puis lit l'adresse réellement jointe.
    nonisolated private static func resolve(_ endpoint: NWEndpoint) async -> DiscoveredServer? {
        guard case let .service(name, _, _, _) = endpoint else { return nil }

        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)

        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint {
                        var address = "\(host)"
                        if let percent = address.firstIndex(of: "%") { address = String(address[..<percent]) }
                        once.finish(DiscoveredServer(name: name, host: address, port: Int(port.rawValue)))
                    } else {
                        once.finish(nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    once.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            // Garde-fou : on abandonne après 5 s
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                once.finish(nil)
                connection.cancel()
            }
        }
    }
}

/// Garantit qu'une continuation n'est reprise qu'une seule fois.
nonisolated private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DiscoveredServer?, Never>?

    init(_ continuation: CheckedContinuation<DiscoveredServer?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: DiscoveredServer?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

// MARK: - Ligne « Mac détecté » (Réglages + introduction)

struct DiscoveredServerRow: View {
    let server: DiscoveredServer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "laptopcomputer")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.subheadline.weight(.semibold))
                    Text("\(server.host) · port \(server.port)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.live)
                } else {
                    Text("Utiliser")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
