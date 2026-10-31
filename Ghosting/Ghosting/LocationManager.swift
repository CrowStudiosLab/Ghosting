import Foundation
import CoreLocation
import Combine

// MARK: - Backend réseau (communique avec le serveur Flask sur ton Mac)

nonisolated struct ServerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated struct MacServerSimulator: LocationSimulating {
    // IP + port du PC : configurables dans Réglages (voir ServerConfig)
    // Mets la même valeur que LOC_TOKEN côté Mac si tu l'as activé, sinon laisse nil
    private let token: String? = nil

    func start(at coordinate: CLLocationCoordinate2D) async throws {
        // Le 1er appel ouvre le tunnel (quelques secondes) : timeout large
        try await post("set-location",
                       body: ["latitude": coordinate.latitude,
                              "longitude": coordinate.longitude],
                       timeout: 30)
    }

    /// Ferme la session côté Mac : l'iPhone retrouve sa vraie position.
    func stop() async throws {
        try await post("clear-location", body: [:], timeout: 15)
    }

    /// Vérifie que le serveur répond (utilisé par « Tester la connexion »).
    func ping() async throws {
        guard let base = ServerConfig.baseURL else { throw ServerConfig.invalidAddressError }
        var request = URLRequest(url: base.appendingPathComponent("status"))
        request.timeoutInterval = 5
        if let token { request.setValue(token, forHTTPHeaderField: "X-Token") }
        let response: URLResponse
        do { (_, response) = try await URLSession.shared.data(for: request) }
        catch is URLError { throw ServerConfig.unreachableError }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw ServerError(message: "Le serveur a répondu avec une erreur (\(http.statusCode)).")
        }
    }

    /// Demande au serveur si une simulation est en cours (route /status).
    func isSimulationActive() async throws -> Bool {
        guard let base = ServerConfig.baseURL else { throw ServerConfig.invalidAddressError }
        var request = URLRequest(url: base.appendingPathComponent("status"))
        request.timeoutInterval = 3
        if let token { request.setValue(token, forHTTPHeaderField: "X-Token") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch is URLError { throw ServerConfig.unreachableError }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["active"] as? Bool ?? false
    }

    private func post(_ path: String, body: [String: Double], timeout: TimeInterval) async throws {
        guard let base = ServerConfig.baseURL else { throw ServerConfig.invalidAddressError }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Token") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch is URLError { throw ServerConfig.unreachableError }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let detail = Self.serverMessage(from: data) ?? "Erreur serveur (\(http.statusCode))"
            throw ServerError(message: detail)
        }
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String, !message.isEmpty else { return nil }
        return String(message.prefix(160))
    }
}

// MARK: - Couche d'abstraction

protocol LocationSimulating: Sendable {
    func start(at coordinate: CLLocationCoordinate2D) async throws
    func stop() async throws
    /// Le Mac simule-t-il encore une position ? (route /status)
    func isSimulationActive() async throws -> Bool
}

/// Backend de dev pour tester sans le Mac.
nonisolated struct LoggingSimulator: LocationSimulating {
    func start(at c: CLLocationCoordinate2D) async throws {
        try await Task.sleep(for: .milliseconds(450))
        print("📍 Injection : \(c.latitude), \(c.longitude)")
    }
    func stop() async throws {
        print("🛑 Simulation arrêtée")
    }
    func isSimulationActive() async throws -> Bool { true }
}

// MARK: - Gestionnaire d'état

@MainActor
final class LocationManager: ObservableObject {
    enum State: Equatable {
        case idle
        case working
        case active(Place)
        case failed(String)
    }

    @Published private(set) var state: State = .idle {
        didSet { updatePolling() }
    }
    /// Erreur survenue à l'arrêt (la simulation reste alors considérée active).
    @Published private(set) var stopError: String?
    private let backend: LocationSimulating
    private let liveActivity = LiveActivityController()
    private var pollTask: Task<Void, Never>?
    /// Lectures « inactif » d'affilée : on en exige deux pour éviter un faux positif juste après le démarrage.
    private var inactiveStreak = 0

    init(backend: LocationSimulating? = nil) {
        self.backend = backend ?? MacServerSimulator()
        // Nettoie une éventuelle activité restée affichée d'un lancement précédent
        Task { await liveActivity.endAll() }
    }

    var activePlace: Place? {
        if case .active(let p) = state { return p }
        return nil
    }

    var isWorking: Bool { state == .working }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return stopError
    }

    func activate(_ place: Place) async {
        guard !isWorking else { return }
        stopError = nil
        state = .working
        do {
            try await backend.start(at: place.coordinate)
            state = .active(place)
            await liveActivity.show(place)   // démarre ou met à jour l'écran de verrouillage / Dynamic Island
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Vérifie auprès du Mac que la simulation tourne toujours. Si elle a été coupée côté Mac
    /// (« Rétablir la vraie position »), l'app repasse en « inactif » et retire la Live Activity.
    /// Un Mac injoignable ne change rien : on ne sait pas, donc on garde l'état.
    func syncWithServer() async {
        guard case .active = state else { inactiveStreak = 0; return }
        guard let stillActive = try? await backend.isSimulationActive() else { return }
        guard case .active = state else { return }   // l'état a pu changer pendant l'appel

        if stillActive {
            inactiveStreak = 0
            return
        }
        inactiveStreak += 1
        guard inactiveStreak >= 2 else { return }

        inactiveStreak = 0
        stopError = nil
        state = .idle
        await liveActivity.end()
    }

    /// Surveille le Mac toutes les 3 s tant qu'une simulation est active.
    private func updatePolling() {
        if case .active = state {
            guard pollTask == nil else { return }
            inactiveStreak = 0
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await self?.syncWithServer()
                }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
            inactiveStreak = 0
        }
    }

    /// Demande au Mac de couper la simulation → retour à la position réelle.
    /// Si l'appel échoue, on reste en état « actif » pour pouvoir réessayer.
    func deactivate() async {
        guard case .active(let place) = state else { return }
        state = .working
        do {
            try await backend.stop()
            stopError = nil
            state = .idle
            await liveActivity.end()
        } catch {
            stopError = "Impossible de rétablir ta position : \(error.localizedDescription)"
            state = .active(place)
        }
    }
}
