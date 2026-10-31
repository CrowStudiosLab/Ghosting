import Foundation
import CoreLocation

/// Un lieu simulable. Hashable/Sendable (contrairement à CLLocationCoordinate2D).
struct Place: Identifiable, Hashable, Sendable, Codable {
    /// Drapeau provisoire tant que le pays n'est pas connu.
    static let unknownFlag = "📍"

    let id: String
    let name: String
    let subtitle: String
    let flag: String
    let latitude: Double
    let longitude: Double
    /// Clé de la suggestion de recherche d'origine : sert à repérer les favoris dans les résultats.
    let sourceKey: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: String = UUID().uuidString, name: String, subtitle: String = "",
         flag: String = Place.unknownFlag, latitude: Double, longitude: Double,
         sourceKey: String? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.flag = flag
        self.latitude = latitude
        self.longitude = longitude
        self.sourceKey = sourceKey
    }

    init(name: String, subtitle: String = "", flag: String = Place.unknownFlag,
         coordinate: CLLocationCoordinate2D, sourceKey: String? = nil) {
        self.init(name: name, subtitle: subtitle, flag: flag,
                  latitude: coordinate.latitude, longitude: coordinate.longitude,
                  sourceKey: sourceKey)
    }
}

extension Place {
    /// IDs stables : la sélection survit aux rechargements de vue.
    static let presets: [Place] = [
        Place(id: "dubai", name: "Dubaï", subtitle: "Émirats arabes unis", flag: "🇦🇪", latitude: 25.2048, longitude: 55.2708),
        Place(id: "marbella", name: "Marbella", subtitle: "Espagne", flag: "🇪🇸", latitude: 36.5101, longitude: -4.8824),
        Place(id: "tokyo", name: "Tokyo", subtitle: "Japon", flag: "🇯🇵", latitude: 35.6762, longitude: 139.6503),
        Place(id: "newyork", name: "New York", subtitle: "États-Unis", flag: "🇺🇸", latitude: 40.7128, longitude: -74.0060),
        Place(id: "paris", name: "Paris", subtitle: "France", flag: "🇫🇷", latitude: 48.8566, longitude: 2.3522)
    ]

    var coordinateLabel: String {
        String(format: "%.4f°, %.4f°", latitude, longitude)
    }

    /// Code pays ISO (« FR ») → drapeau (🇫🇷).
    static func flagEmoji(forCountryCode code: String) -> String {
        let base: UInt32 = 127397
        return code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(base + $0.value) }
            .map { String($0) }
            .joined()
    }
}
