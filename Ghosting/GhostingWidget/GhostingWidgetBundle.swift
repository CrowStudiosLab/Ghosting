import SwiftUI
import WidgetKit

// Cible : extension Widget uniquement.
@main
struct GhostingWidgetBundle: WidgetBundle {
    var body: some Widget {
        GhostingLiveActivity()
    }
}
