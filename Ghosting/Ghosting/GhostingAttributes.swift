import ActivityKit
import Foundation

/// Partagé entre l'app ET l'extension Widget (cocher les deux dans Target Membership).
nonisolated struct GhostingAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var placeName: String
        var subtitle: String
        var flag: String
        var coordinateLabel: String
    }

    /// Heure de début, pour le chronomètre « actif depuis… ».
    var startedAt: Date
}
