import Foundation

// MARK: - Client HTTP du server.py embarqué (en local)

nonisolated struct ServerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Réponse de la route /status.
nonisolated struct ServerStatus: Sendable, Equatable {
    let active: Bool
    let latitude: Double?
    let longitude: Double?

    var coordinateLabel: String? {
        guard let latitude, let longitude else { return nil }
        return String(format: "%.4f°, %.4f°", latitude, longitude)
    }
}

nonisolated struct LocalServerClient: Sendable {
    /// Vérifie que le serveur répond (démarrage).
    func ping() async throws {
        _ = try await get("status", timeout: 5)
    }

    func status() async throws -> ServerStatus {
        let data = try await get("status", timeout: 3)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ServerStatus(active: json?["active"] as? Bool ?? false,
                            latitude: json?["latitude"] as? Double,
                            longitude: json?["longitude"] as? Double)
    }

    func isSimulationActive() async throws -> Bool {
        try await status().active
    }

    /// Ferme la session côté serveur : l'iPhone retrouve sa vraie position.
    func stop(timeout: TimeInterval = 15) async throws {
        var request = try makeRequest("clear-location", method: "POST", timeout: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        _ = try await send(request)
    }

    /// `true` si quelque chose répond déjà sur le port (ancienne instance de server.py, autre programme…).
    /// Toute réponse HTTP compte, même un 401 : seul un refus de connexion signifie « port libre ».
    static func isPortBusy() async -> Bool {
        guard let base = ServerConfig.baseURL else { return false }
        var request = URLRequest(url: base.appendingPathComponent("status"))
        request.timeoutInterval = 1.5
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return false
        }
    }

    // MARK: Requêtes

    private func makeRequest(_ path: String, method: String, timeout: TimeInterval) throws -> URLRequest {
        guard let base = ServerConfig.baseURL else { throw ServerConfig.unreachableError }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        if !ServerConfig.token.isEmpty {
            request.setValue(ServerConfig.token, forHTTPHeaderField: "X-Token")
        }
        return request
    }

    private func get(_ path: String, timeout: TimeInterval) async throws -> Data {
        try await send(try makeRequest(path, method: "GET", timeout: timeout))
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch is URLError { throw ServerConfig.unreachableError }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let detail = Self.serverMessage(from: data) ?? "Erreur serveur (\(http.statusCode))"
            throw ServerError(message: detail)
        }
        return data
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String, !message.isEmpty else { return nil }
        return String(message.prefix(160))
    }
}
