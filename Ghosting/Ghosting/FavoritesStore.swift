import Foundation
import Combine

/// Lieux favoris, conservés entre deux lancements de l'app (UserDefaults).
@MainActor
final class FavoritesStore: ObservableObject {
    private static let key = "favorites.places"

    @Published private(set) var places: [Place] = []

    init() { load() }

    /// Ajoute un lieu. Renvoie `false` s'il est déjà dans les favoris.
    @discardableResult
    func add(_ place: Place) -> Bool {
        guard !contains(place) else { return false }
        places.append(place)
        save()
        return true
    }

    func remove(_ place: Place) {
        places.removeAll { $0.id == place.id }
        save()
    }

    /// Même lieu = même nom + même pays, ou coordonnées quasi identiques (~100 m).
    func contains(_ place: Place) -> Bool {
        places.contains { fav in
            if fav.id == place.id { return true }
            let sameName = fav.name.caseInsensitiveCompare(place.name) == .orderedSame
                && fav.subtitle.caseInsensitiveCompare(place.subtitle) == .orderedSame
            let close = abs(fav.latitude - place.latitude) < 0.001
                && abs(fav.longitude - place.longitude) < 0.001
            return sameName || close
        }
    }

    /// Favori correspondant à une suggestion de recherche (pour l'étoile et le menu).
    func match(_ suggestion: Suggestion) -> Place? {
        places.first { $0.sourceKey == suggestion.key }
            ?? places.first {   // favoris enregistrés avant l'ajout de la clé
                $0.sourceKey == nil
                    && Suggestion.normalize($0.name) == Suggestion.normalize(suggestion.title)
            }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Place].self, from: data) else { return }
        places = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
