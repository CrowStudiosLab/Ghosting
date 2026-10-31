import Foundation
import Combine

/// Lance `server.py` (embarqué dans l'app) avec `Process`, surveille son état, récupère son journal
/// et l'arrête proprement.
///
/// Arrêt « propre » en 4 temps :
///   1. `POST /clear-location` → l'iPhone retrouve sa vraie position ;
///   2. `SIGINT` → Python exécute ses handlers `atexit` (fermeture de la session DVT) ;
///   3. `SIGTERM` si le processus traîne ;
///   4. `SIGKILL` en dernier recours.
@MainActor
final class ServerProcess: ObservableObject {
    static let shared = ServerProcess()

    enum State: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case failed(String)
    }

    @Published private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            updateBonjour()
        }
    }
    @Published private(set) var logLines: [String] = []

    var isRunning: Bool { state == .running }
    var logText: String { logLines.joined(separator: "\n") }

    /// Interpréteur retenu au dernier démarrage (réutilisé pour détecter l'iPhone).
    private(set) var pythonExecutable: String?

    /// Annonce le serveur sur le réseau local tant qu'il tourne.
    private let bonjour = BonjourAdvertiser()

    private var process: Process?
    private var outputPipe: Pipe?
    private var partialLine = ""
    private let maxLogLines = 500

    /// Interpréteurs essayés dans l'ordre quand aucun chemin n'est configuré.
    private static let pythonCandidates = [
        "/opt/homebrew/bin/python3",                                   // Homebrew (Apple Silicon)
        "/usr/local/bin/python3",                                      // Homebrew (Intel)
        "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", // python.org
        "/usr/bin/python3"                                             // Outils Xcode
    ]

    private init() {}

    // MARK: Démarrage

    func start() async {
        switch state {
        case .starting, .running, .stopping: return
        case .stopped, .failed: break
        }
        state = .starting
        log("▶︎ Démarrage du serveur Ghosting…")

        guard let script = Bundle.main.url(forResource: "server", withExtension: "py") else {
            return fail("server.py est introuvable dans l'app (Build Phases > Copy Bundle Resources).")
        }

        let port = ServerConfig.port
        if await LocalServerClient.isPortBusy() {
            return fail("Le port \(port) est déjà utilisé (ancienne instance de server.py ?). Ferme-la ou change le port dans les réglages.")
        }
        guard state == .starting else { return }

        // Interpréteur Python
        // Chemin des Réglages ; à défaut, le venv par défaut s'il existe ; sinon détection automatique
        let configured = (ServerConfig.pythonPath as NSString).expandingTildeInPath
        let custom = (configured.isEmpty && FileManager.default.isExecutableFile(atPath: ServerConfig.defaultPythonPath))
            ? ServerConfig.defaultPythonPath
            : configured
        let python: String
        if !custom.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: custom) else {
                return fail("Python introuvable à l'emplacement indiqué : \(custom)")
            }
            python = custom
        } else if let found = Self.pythonCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            python = found
        } else {
            return fail("Python 3 est introuvable. Installe-le (brew install python) ou indique son chemin dans les réglages.")
        }
        pythonExecutable = python
        log("Python : \(python)")

        // Dépendances (message clair plutôt qu'un crash au lancement)
        if let problem = await Self.checkDependencies(python: python) {
            return fail(problem)
        }
        guard state == .starting else { return }

        // Processus
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-u", script.path]
        p.currentDirectoryURL = FileManager.default.temporaryDirectory

        var env = ProcessInfo.processInfo.environment
        env["LOC_HOST"] = ServerConfig.listenHost   // 0.0.0.0 : joignable par l'iPhone sur le Wi-Fi
        env["LOC_PORT"] = String(port)
        env["LOC_TOKEN"] = nil
        if !ServerConfig.token.isEmpty { env["LOC_TOKEN"] = ServerConfig.token }
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        // Une app lancée depuis le Finder a un PATH minimal
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        if !ServerConfig.udid.isEmpty { env["LOC_UDID"] = ServerConfig.udid }
        p.environment = env

        // Sortie standard + erreurs → journal
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.ingest(text) }
        }

        p.terminationHandler = { [weak self] proc in
            let pid = proc.processIdentifier
            let status = proc.terminationStatus
            Task { @MainActor [weak self] in self?.processDidExit(pid: pid, status: status) }
        }

        do {
            try p.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return fail("Impossible de lancer Python : \(error.localizedDescription)")
        }
        process = p
        outputPipe = pipe
        log("Processus lancé (pid \(p.processIdentifier)). En attente du serveur…")

        // On attend que Flask réponde (l'import de pymobiledevice3 peut prendre quelques secondes)
        let client = LocalServerClient()
        let deadline = Date().addingTimeInterval(45)
        while state == .starting, Date() < deadline {
            if (try? await client.ping()) != nil {
                state = .running
                log("✓ Serveur prêt (port \(port))")
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        if state == .starting {
            await stop(timeout: 2)
            fail("Le serveur ne répond pas après 45 s. Consulte le journal dans les réglages.")
        }
    }

    // MARK: Arrêt

    func stop(timeout: TimeInterval = 15) async {
        guard let proc = process, proc.isRunning else {
            process = nil
            state = .stopped
            return
        }
        if state == .stopping {
            _ = await waitForExit(proc, seconds: 12)
            return
        }
        state = .stopping
        log("■ Arrêt du serveur…")

        // 1. Rétablir la vraie position de l'iPhone
        let client = LocalServerClient()
        if (try? await client.isSimulationActive()) == true {
            log("Rétablissement de la position réelle…")
            try? await client.stop(timeout: timeout)
        }

        // 2. SIGINT : Python exécute ses handlers atexit
        let pid = proc.processIdentifier
        kill(pid, SIGINT)
        var exited = await waitForExit(proc, seconds: 6)

        // 3. SIGTERM
        if !exited {
            proc.terminate()
            exited = await waitForExit(proc, seconds: 3)
        }
        // 4. SIGKILL
        if !exited {
            kill(pid, SIGKILL)
            _ = await waitForExit(proc, seconds: 2)
        }

        if process?.processIdentifier == pid {
            process = nil
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            outputPipe = nil
        }
        state = .stopped
        log("■ Serveur arrêté.")
    }

    func restart() async {
        await stop()
        await start()
    }

    // MARK: Interne

    /// Publie le service Bonjour quand le serveur tourne, le retire dans tous les autres cas.
    private func updateBonjour() {
        if state == .running {
            bonjour.publish(port: ServerConfig.port)
        } else {
            bonjour.stop()
        }
    }

    private func processDidExit(pid: Int32, status: Int32) {
        guard process?.processIdentifier == pid else { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        flushPartialLine()

        switch state {
        case .stopping:
            state = .stopped
        case .starting, .running:
            log("✗ Le serveur s'est arrêté (code \(status)).")
            state = .failed("Le serveur s'est arrêté de façon inattendue (code \(status)). Consulte le journal dans les réglages.")
        case .stopped, .failed:
            break
        }
    }

    private func waitForExit(_ proc: Process, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while proc.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return !proc.isRunning
    }

    private func fail(_ message: String) {
        log("✗ \(message)")
        state = .failed(message)
    }

    // MARK: Journal

    private func ingest(_ text: String) {
        partialLine += text
        var parts = partialLine.components(separatedBy: "\n")
        partialLine = parts.removeLast()
        for part in parts {
            let line = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { log(line) }
        }
    }

    private func flushPartialLine() {
        let line = partialLine.trimmingCharacters(in: .whitespacesAndNewlines)
        partialLine = ""
        if !line.isEmpty { log(line) }
    }

    private func log(_ line: String) {
        logLines.append(line)
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
    }

    /// Vérifie que flask et pymobiledevice3 sont importables avec cet interpréteur.
    /// Renvoie un message d'erreur, ou nil si tout est en place.
    nonisolated private static func checkDependencies(python: String) async -> String? {
        await Task.detached { () -> String? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: python)
            p.arguments = ["-c", "import flask, pymobiledevice3"]
            let errors = Pipe()
            p.standardError = errors
            p.standardOutput = FileHandle.nullDevice
            do { try p.run() } catch {
                return "Impossible de lancer Python (\(python)) : \(error.localizedDescription)"
            }
            let output = errors.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus != 0 else { return nil }
            let last = String(decoding: output, as: UTF8.self)
                .split(separator: "\n").last.map(String.init) ?? "erreur inconnue"
            return "Modules Python manquants (\(last)). Installe-les avec : \(python) -m pip install flask pymobiledevice3"
        }.value
    }
}
