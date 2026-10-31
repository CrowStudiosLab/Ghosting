import Foundation
import SwiftUI
import Combine

// MARK: - Lancer des processus

nonisolated enum Shell {
    struct Output: Sendable {
        let status: Int32
        let output: String
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Une app lancée depuis le Finder a un PATH minimal
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        env["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        return env
    }

    /// Lance une commande et attend sa fin (avec un délai maximum).
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async -> Output {
        await Task.detached { () -> Output in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch {
                return Output(status: -1, output: error.localizedDescription)
            }
            let box = ProcessBox(process)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if box.process.isRunning { box.process.terminate() }
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Output(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Lance une commande longue et renvoie sa sortie ligne par ligne.
    static func stream(_ executable: String, _ arguments: [String],
                       onLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment()

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = LineBuffer(onLine)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    buffer.flush()
                } else {
                    buffer.append(data)
                }
            }
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                onLine(error.localizedDescription)
                continuation.resume(returning: -1)
            }
        }
    }
}

nonisolated private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

nonisolated private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var partial = ""
    private let onLine: @Sendable (String) -> Void

    init(_ onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        partial += text
        var parts = partial.components(separatedBy: "\n")
        partial = parts.removeLast()
        lock.unlock()
        for part in parts { emit(part) }
    }

    func flush() {
        lock.lock()
        let rest = partial
        partial = ""
        lock.unlock()
        emit(rest)
    }

    private func emit(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { onLine(line) }
    }
}

// MARK: - Un Python trouvé

nonisolated struct PythonCandidate: Identifiable, Equatable, Sendable {
    let path: String
    let version: String
    /// `flask` et `pymobiledevice3` sont importables avec cet interpréteur.
    let hasDeps: Bool

    var id: String { path }
    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

// MARK: - Recherche et vérification (hors MainActor)

nonisolated enum PythonProbe {
    static let packages = ["flask", "pymobiledevice3"]
    static let minimumMinor = 9   // Python 3.9 ou plus récent

    /// Environnement Python créé par l'app quand le Python choisi ne peut pas être modifié (Homebrew, système…).
    static var managedVenvDirectory: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Library/Application Support"
        return base + "/Ghosting Server/venv"
    }

    static var managedPython: String { managedVenvDirectory + "/bin/python3" }

    /// Vrai si l'interpréteur est dans un environnement virtuel (présence de `pyvenv.cfg`).
    static func isVirtualEnv(_ python: String) -> Bool {
        let root = ((python as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        return FileManager.default.fileExists(atPath: root + "/pyvenv.cfg")
    }

    /// Vérifie un interpréteur : version (3.9+) et dépendances.
    static func inspect(_ path: String) async -> PythonCandidate? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let versionRun = await Shell.run(path, ["-c", "import sys; print('%d.%d.%d' % sys.version_info[:3])"], timeout: 10)
        guard versionRun.status == 0,
              let last = versionRun.output.split(separator: "\n").last else { return nil }
        let version = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2, parts[0] == 3, parts[1] >= minimumMinor else { return nil }

        let deps = await Shell.run(path, ["-c", "import flask, pymobiledevice3"], timeout: 60)
        return PythonCandidate(path: path, version: version, hasDeps: deps.status == 0)
    }

    /// Cherche tous les Python utilisables, ceux qui ont déjà les dépendances en premier.
    static func findCandidates() async -> [PythonCandidate] {
        let paths = await candidatePaths()
        let found = await withTaskGroup(of: PythonCandidate?.self) { group in
            for path in paths { group.addTask { await inspect(path) } }
            var result: [PythonCandidate] = []
            for await candidate in group { if let candidate { result.append(candidate) } }
            return result
        }
        return found.sorted { a, b in
            if a.hasDeps != b.hasDeps { return a.hasDeps }
            // Version la plus récente d'abord
            return versionNumbers(b.version).lexicographicallyPrecedes(versionNumbers(a.version))
        }
    }

    private static func versionNumbers(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }

    private static func candidatePaths() async -> [String] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var list: [String] = []

        // Ce que l'utilisateur ou l'app a déjà choisi
        let configured = (ServerConfig.pythonPath as NSString).expandingTildeInPath
        if !configured.isEmpty { list.append(configured) }
        list.append(ServerConfig.defaultPythonPath)
        list.append(managedPython)

        // Homebrew (Apple Silicon et Intel)
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            list.append("\(dir)/python3")
            for minor in minimumMinor...14 { list.append("\(dir)/python3.\(minor)") }
        }
        // python.org
        let framework = "/Library/Frameworks/Python.framework/Versions"
        for version in (try? fm.contentsOfDirectory(atPath: framework)) ?? [] {
            list.append("\(framework)/\(version)/bin/python3")
        }
        // pyenv
        let pyenv = home + "/.pyenv/versions"
        for version in (try? fm.contentsOfDirectory(atPath: pyenv)) ?? [] {
            list.append("\(pyenv)/\(version)/bin/python3")
        }
        list += [
            home + "/.pyenv/shims/python3",
            home + "/miniconda3/bin/python3",
            home + "/anaconda3/bin/python3",
            "/opt/homebrew/Caskroom/miniconda/base/bin/python3",
            "/Library/Developer/CommandLineTools/usr/bin/python3"   // Outils Xcode (vrai binaire, pas le raccourci /usr/bin)
        ]

        // PATH du shell de l'utilisateur
        let which = await Shell.run("/bin/zsh", ["-lc", "which -a python3"], timeout: 8)
        for line in which.output.split(separator: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("/") { list.append(path) }
        }

        // Doublons retirés. /usr/bin/python3 est ignoré : sans les Outils Xcode il ouvre une fenêtre d'installation.
        var seen = Set<String>()
        var result: [String] = []
        for path in list where !path.isEmpty && path != "/usr/bin/python3" {
            guard fm.isExecutableFile(atPath: path) else { continue }
            // Un venv pointe vers son Python de base : on garde son chemin tel quel pour ne pas le confondre
            let key = isVirtualEnv(path) ? path : URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            if seen.insert(key).inserted { result.append(path) }
        }
        return result
    }
}

// MARK: - État partagé par l'introduction

@MainActor
final class PythonSetup: ObservableObject {
    enum InstallState: Equatable {
        case idle
        case installing
        case success
        case failure(String)
    }

    @Published private(set) var candidates: [PythonCandidate] = []
    @Published private(set) var selected: PythonCandidate?
    @Published private(set) var isScanning = false
    @Published private(set) var isChecking = false
    @Published private(set) var invalidMessage: String?
    @Published private(set) var installState: InstallState = .idle
    @Published private(set) var installLog: [String] = []

    private var hasScanned = false

    // MARK: Recherche

    /// Cherche automatiquement. Ne refait pas la recherche d'office si elle a déjà eu lieu (`force`).
    func scan(force: Bool = false) {
        guard !isScanning, force || !hasScanned else { return }
        hasScanned = true
        isScanning = true
        invalidMessage = nil

        Task {
            let found = await PythonProbe.findCandidates()
            // On garde un Python choisi à la main même s'il n'apparaît pas dans la recherche
            let manual = candidates.filter { old in !found.contains { $0.path == old.path } && old.path == selected?.path }
            candidates = manual + found
            isScanning = false

            if let current = selected, let updated = candidates.first(where: { $0.path == current.path }) {
                selected = updated
            } else if let configured = candidates.first(where: {
                $0.path == (ServerConfig.pythonPath as NSString).expandingTildeInPath
            }) {
                choose(configured)
            } else if let best = candidates.first {
                choose(best)
            }
        }
    }

    func choose(_ candidate: PythonCandidate) {
        selected = candidate
        invalidMessage = nil
        installState = .idle
        UserDefaults.standard.set(candidate.path, forKey: ServerConfig.pythonPathKey)
    }

    /// Fenêtre de sélection de fichier, puis vérification du Python choisi.
    func pickManually() async {
        guard let path = PythonPicker.choose() else { return }
        isChecking = true
        invalidMessage = nil
        let candidate = await PythonProbe.inspect(path)
        isChecking = false

        guard let candidate else {
            invalidMessage = "Ce fichier n'est pas un Python 3.\(PythonProbe.minimumMinor) ou plus récent."
            return
        }
        if !candidates.contains(where: { $0.path == candidate.path }) { candidates.insert(candidate, at: 0) }
        choose(candidate)
    }

    // MARK: Installation

    /// Installe flask et pymobiledevice3. Si le Python choisi n'est pas un environnement virtuel
    /// (Homebrew refuse `pip install` hors venv), un environnement dédié est créé d'abord.
    func install() async {
        guard let base = selected, installState != .installing else { return }
        installState = .installing
        installLog = []

        var target = base.path
        if !PythonProbe.isVirtualEnv(base.path) {
            append("Création d'un environnement Python dédié…")
            let directory = PythonProbe.managedVenvDirectory
            try? FileManager.default.createDirectory(
                atPath: (directory as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            let status = await Shell.stream(base.path, ["-m", "venv", "--clear", directory]) { [weak self] line in
                Task { @MainActor in self?.append(line) }
            }
            guard status == 0 else {
                installState = .failure("Impossible de créer l'environnement Python. Consulte les détails.")
                return
            }
            target = PythonProbe.managedPython
        }

        append("Installation de \(PythonProbe.packages.joined(separator: " et "))…")
        let status = await Shell.stream(target, ["-m", "pip", "install", "--upgrade"] + PythonProbe.packages) { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }
        guard status == 0 else {
            installState = .failure("L'installation a échoué. Vérifie ta connexion internet puis réessaie.")
            return
        }

        guard let installed = await PythonProbe.inspect(target), installed.hasDeps else {
            installState = .failure("Les modules sont installés mais ne se chargent pas. Consulte les détails.")
            return
        }
        if let index = candidates.firstIndex(where: { $0.path == installed.path }) {
            candidates[index] = installed
        } else {
            candidates.insert(installed, at: 0)
        }
        choose(installed)           // enregistre aussi le nouveau chemin dans les réglages
        installState = .success
        append("✓ Dépendances installées.")
    }

    private func append(_ line: String) {
        installLog.append(line)
        if installLog.count > 400 { installLog.removeFirst(installLog.count - 400) }
    }
}
