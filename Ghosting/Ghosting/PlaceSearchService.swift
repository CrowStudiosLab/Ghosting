import Foundation
import MapKit
import CoreLocation
import Combine

struct Suggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion

    /// Identifie la suggestion (titre + sous-titre, sans casse ni accents).
    var key: String { Self.normalize("\(title)|\(subtitle)") }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}

enum PlaceSearchError: LocalizedError {
    case noResult
    var errorDescription: String? { "Aucun résultat pour cette adresse." }
}

/// Pays / ville retrouvés à partir de coordonnées.
struct GeoInfo: Sendable {
    let flag: String
    let country: String
    let locality: String?
}

/// Auto-complétion + résolution d'adresse via MapKit (MKLocalSearch).
final class PlaceSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [Suggestion] = []
    @Published var query: String = "" {
        didSet { update(query) }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    private func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            suggestions = []
            completer.cancel()
        } else {
            completer.queryFragment = trimmed
        }
    }

    func clear() {
        query = ""
        suggestions = []
    }

    /// Pays (et drapeau) d'un point GPS. Renvoie nil en pleine mer ou hors connexion.
    func country(at coordinate: CLLocationCoordinate2D) async -> GeoInfo? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
              let code = mark.isoCountryCode, code.count == 2 else { return nil }
        return GeoInfo(flag: Place.flagEmoji(forCountryCode: code),
                       country: mark.country ?? "",
                       locality: mark.locality)
    }

    func resolve(_ suggestion: Suggestion) async throws -> Place {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw PlaceSearchError.noResult }
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }

        let info = await country(at: coordinate)
        let subtitle: String = {
            if let country = info?.country, !country.isEmpty { return country }
            return suggestion.subtitle
        }()
        return Place(name: suggestion.title,
                     subtitle: subtitle,
                     flag: info?.flag ?? Place.unknownFlag,
                     coordinate: coordinate,
                     sourceKey: suggestion.key)
    }

    // MARK: MKLocalSearchCompleterDelegate (appelé sur le main thread)
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(6).map {
            Suggestion(title: $0.title, subtitle: $0.subtitle, completion: $0)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
