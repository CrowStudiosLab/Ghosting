import Foundation
import CoreLocation
import Combine

/// Position RÉELLE de l'iPhone.
/// Pendant une simulation, CoreLocation renvoie la position simulée : le fournisseur est alors « gelé »
/// et la dernière vraie position est conservée sur l'appareil.
@MainActor
final class UserLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    nonisolated private static let latKey = "realLocation.latitude"
    nonisolated private static let lonKey = "realLocation.longitude"

    /// Dernière vraie position reçue pendant cette session.
    @Published private(set) var location: CLLocation?

    /// Gelé par défaut : l'app le libère une fois qu'elle sait qu'aucune simulation n'est en cours.
    var isFrozen = true

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Dernière vraie position enregistrée (disponible dès le lancement, avant tout nouveau relevé).
    nonisolated static func storedCoordinate() -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: latKey) != nil,
              defaults.object(forKey: lonKey) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: defaults.double(forKey: latKey),
                                      longitude: defaults.double(forKey: lonKey))
    }

    /// Demande la permission si besoin, puis relève la position (sans effet si gelé).
    func refresh() {
        guard !isFrozen else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    private func receive(_ newLocation: CLLocation) {
        guard !isFrozen else { return }
        UserDefaults.standard.set(newLocation.coordinate.latitude, forKey: Self.latKey)
        UserDefaults.standard.set(newLocation.coordinate.longitude, forKey: Self.lonKey)
        location = newLocation
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.receive(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Pas de position (refus, pas de signal…) : on garde la dernière connue.
    }
}
