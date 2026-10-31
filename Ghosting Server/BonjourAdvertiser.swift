import Foundation

/// Annonce le serveur Ghosting sur le réseau local (Bonjour / mDNS) pour que l'app iPhone le trouve seule.
/// Service : `_ghosting._tcp` sur le port du serveur Flask. Appelé par `ServerProcess` selon son état.
@MainActor
final class BonjourAdvertiser: NSObject, NetServiceDelegate {
    static let serviceType = "_ghosting._tcp."

    private var service: NetService?

    /// (Re)publie le service. Le nom affiché sur l'iPhone est le nom du Mac.
    func publish(port: Int) {
        stop()
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let service = NetService(domain: "", type: Self.serviceType, name: name, port: Int32(port))
        service.delegate = self
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "app": Data("ghosting".utf8),
            "v": Data("1".utf8)
        ]))
        service.publish()
        self.service = service
    }

    func stop() {
        service?.stop()
        service = nil
    }

    // MARK: NetServiceDelegate

    nonisolated func netServiceDidPublish(_ sender: NetService) {
        print("📡 Bonjour : « \(sender.name) » annoncé sur le port \(sender.port)")
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        print("❌ Bonjour : publication impossible \(errorDict)")
    }
}
