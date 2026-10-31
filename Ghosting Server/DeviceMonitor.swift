import Foundation
import Combine

/// Surveille toutes les 3 s : iPhone branché en USB, simulation en cours, adresse IP du Mac.
@MainActor
final class DeviceMonitor: ObservableObject {
    enum Phone: Equatable {
        case unknown
        case disconnected
        case connected(String)      // USB
        case wireless(String)       // Wi-Fi (synchronisation Wi-Fi activée sur l'iPhone)
    }

    @Published private(set) var phone: Phone = .unknown
    @Published private(set) var simulation: ServerStatus?
    @Published private(set) var localIP: String?

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func poll() async {
        localIP = LocalNetwork.ipv4Address()

        let server = ServerProcess.shared
        if server.isRunning {
            simulation = try? await LocalServerClient().status()
        } else {
            simulation = nil
        }

        if let python = server.pythonExecutable {
            phone = await Self.queryPhone(python: python)
        }
    }

    /// `python -m pymobiledevice3 usbmux list` : liste les appareils reliés en USB ou joignables en Wi-Fi (sans droits root).
    nonisolated private static func queryPhone(python: String) async -> Phone {
        await Task.detached { () -> Phone in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: python)
            p.arguments = ["-m", "pymobiledevice3", "usbmux", "list"]
            let output = Pipe()
            p.standardOutput = output
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return .unknown }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0,
                  let devices = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return .unknown }

            // Le câble est prioritaire ; sinon un iPhone joignable en Wi-Fi compte aussi
            if let usb = devices.first(where: { ($0["ConnectionType"] as? String ?? "USB") == "USB" }) {
                return .connected(usb["DeviceName"] as? String ?? "iPhone")
            }
            if let wifi = devices.first(where: { ($0["ConnectionType"] as? String) == "Network" }) {
                return .wireless(wifi["DeviceName"] as? String ?? "iPhone")
            }
            return .disconnected
        }.value
    }
}
