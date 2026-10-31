import ActivityKit
import Foundation

/// Pilote la Live Activity (écran de verrouillage + Dynamic Island). Cible : app uniquement.
@MainActor
final class LiveActivityController {
    private var activity: Activity<GhostingAttributes>?

    /// Démarre l'activité, ou la met à jour si elle existe déjà (changement de lieu).
    func show(_ place: Place) async {
        let state = GhostingAttributes.ContentState(
            placeName: place.name,
            subtitle: place.subtitle,
            flag: place.flag,
            coordinateLabel: place.coordinateLabel
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity {
            await activity.update(content)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("ℹ️ Live Activities désactivées (Réglages > Ghosting)")
            return
        }
        do {
            activity = try Activity.request(
                attributes: GhostingAttributes(startedAt: .now),
                content: content,
                pushType: nil
            )
        } catch {
            print("❌ Live Activity : \(error.localizedDescription)")
        }
    }

    /// Retire l'activité de l'écran de verrouillage et de la Dynamic Island.
    func end() async {
        await endAll()
        activity = nil
    }

    /// Termine toute activité restante (ex. après un relancement de l'app).
    func endAll() async {
        for existing in Activity<GhostingAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }
}
