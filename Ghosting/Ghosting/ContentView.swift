import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject private var manager: LocationManager
    @EnvironmentObject private var search: PlaceSearchService

    // Démarre sur la dernière vraie position connue (sinon Paris), mise à jour dès qu'un relevé arrive
    @State private var position: MapCameraPosition = .region(ContentView.initialPlace().region)
    @State private var selected: Place = ContentView.initialPlace()
    @State private var hasChosen = false
    @StateObject private var userLocation = UserLocationProvider()
    @State private var localError: String?
    @State private var isStopping = false
    @StateObject private var favorites = FavoritesStore()
    @State private var showSettings = false
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool

    /// Recherche en cours (clavier ouvert ou suggestions affichées) : le panneau du bas est masqué.
    private var isSearching: Bool { searchFocused || !search.suggestions.isEmpty }

    // MARK: Marqueurs

    /// Vraie position de l'iPhone (dernier relevé, sinon dernière position enregistrée).
    private var realCoordinate: CLLocationCoordinate2D? {
        userLocation.location?.coordinate ?? UserLocationProvider.storedCoordinate()
    }

    private func isSameSpot(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < 40
    }

    /// Le lieu sélectionné est à l'endroit où se trouve réellement l'iPhone.
    private var selectedAtReal: Bool {
        guard let real = realCoordinate else { return false }
        return selected.id == Self.homeID || isSameSpot(selected.coordinate, real)
    }

    /// Le pin du lieu sélectionné « fusionne » avec ma position : simulation ici, ou lieu = vraie position.
    private var selectedIsMe: Bool { isActiveHere || (!isActive && selectedAtReal) }

    /// Point bleu à part, sauf s'il est déjà fusionné dans un pin.
    private var showRealDot: Bool {
        guard let real = realCoordinate, !selectedAtReal else { return false }
        if let sim = manager.activePlace, isSameSpot(sim.coordinate, real) { return false }
        return true
    }

    private var isActive: Bool { manager.activePlace != nil }
    /// On compare les ids : le drapeau/pays d'un lieu peut être complété après coup.
    private var isActiveHere: Bool { manager.activePlace?.id == selected.id }
    private var errorText: String? { localError ?? manager.errorMessage }

    var body: some View {
        ZStack {
            mapLayer
            scrims

            VStack(spacing: 12) {
                header
                searchBar
                if !search.suggestions.isEmpty { suggestionList }
                Spacer()
                // Masqué pendant la recherche : sinon le clavier le fait remonter et il chevauche l'interface
                if !isSearching {
                    VStack(spacing: 12) {
                        if realCoordinate != nil {
                            HStack {
                                Spacer()
                                recenterButton
                            }
                        }
                        bottomPanel
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            // Le clavier ne doit pas repousser l'interface vers le haut (header coupé sous la barre d'état)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .animation(.smooth(duration: 0.35), value: search.suggestions.count)
        .animation(.smooth(duration: 0.35), value: isSearching)
        .animation(.smooth(duration: 0.35), value: manager.state)
        .animation(.smooth(duration: 0.35), value: errorText)
        .sensoryFeedback(.success, trigger: manager.activePlace)
        .sensoryFeedback(.success, trigger: favorites.places)
        .sensoryFeedback(.error, trigger: errorText) { _, new in new != nil }
        .onAppear { focus(on: selected) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { await startLocationTracking() }
        .onChange(of: manager.state) {
            // Pendant une simulation, CoreLocation renverrait la position simulée : on gèle les relevés
            userLocation.isFrozen = manager.isWorking || manager.activePlace != nil
        }
        .onChange(of: userLocation.location) { _, new in
            guard let new else { return }
            applyHome(at: new.coordinate, focusMap: !hasChosen)
        }
    }

    // MARK: Carte

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $position) {
                // Vraie position : point bleu (estompé pendant une simulation)
                if showRealDot, let real = realCoordinate {
                    Annotation("Ma position", coordinate: real, anchor: .center) {
                        UserDot(dimmed: isActive)
                    }
                }
                // Simulation active ailleurs que sur le lieu sélectionné : son pin reste visible
                if let sim = manager.activePlace, !isActiveHere {
                    Annotation(sim.name, coordinate: sim.coordinate, anchor: .center) {
                        GhostPin(isActive: true, isMe: true)
                    }
                }
                // Lieu sélectionné
                Annotation(selected.name, coordinate: selected.coordinate, anchor: .center) {
                    GhostPin(isActive: isActiveHere, isMe: selectedIsMe)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted,
                                pointsOfInterest: .excludingAll))
            .onTapGesture { point in
                guard let c = proxy.convert(point, from: .local) else { return }
                searchFocused = false
                search.clear()
                choose(Place(name: "Point personnalisé",
                             subtitle: "Choisi sur la carte",
                             coordinate: c))
            }
        }
        .ignoresSafeArea()
    }

    private var scrimColor: Color { colorScheme == .dark ? Color(hex: "0A0F20") : .white }

    private var scrims: some View {
        ZStack {
            VStack {
                LinearGradient(colors: [scrimColor.opacity(0.6), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                Spacer()
            }
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, scrimColor.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 380)
            }
            // halo coloré derrière le panneau : vert quand la simulation est active
            RadialGradient(colors: [(isActive ? Theme.live : Theme.glow).opacity(0.4), .clear],
                           center: .bottom, startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Header & recherche

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                searchFocused = false
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .glass(radius: 23, interactive: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Réglages")
            Text("Ghosting")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Spacer()
            StatusChip(state: manager.state)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher une adresse ou un lieu", text: $search.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !search.query.isEmpty {
                Button { search.clear() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .glass(radius: 26, interactive: true)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(search.suggestions) { s in
                Button { pick(s) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.subheadline.weight(.semibold))
                            if !s.subtitle.isEmpty {
                                Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if favorites.match(s) != nil {
                            Image(systemName: "star.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { pick(s) } label: {
                        Label("Choisir cette localisation", systemImage: "mappin.and.ellipse")
                    }
                    if favorites.match(s) != nil {
                        Button(role: .destructive) { toggleFavorite(s) } label: {
                            Label("Retirer des favoris", systemImage: "star.slash")
                        }
                    } else {
                        Button { toggleFavorite(s) } label: {
                            Label("Ajouter aux favoris", systemImage: "star")
                        }
                    }
                }
                if s.id != search.suggestions.last?.id {
                    Divider().overlay(Color.primary.opacity(0.1)).padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
        .glass(radius: 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Panneau du bas

    private var bottomPanel: some View {
        VStack(spacing: 16) {
            if !favorites.places.isEmpty { favoritesBar }
            placeRow

            if let errorText {
                ErrorPill(text: errorText)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            actionButton

            if isActiveHere {
                Text("Ta vraie position sera rétablie à l'arrêt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(18)
        .glass(radius: 34)
    }

    private var favoritesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(favorites.places) { place in
                    let isSel = selected.id == place.id
                    Button { choose(place) } label: {
                        HStack(spacing: 6) {
                            Text(place.flag)
                            Text(place.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSel ? Theme.onAccent : Color.primary)
                        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 9)
                        .background {
                            Capsule().fill(isSel ? AnyShapeStyle(Theme.accent)
                                                 : AnyShapeStyle(Color.primary.opacity(0.1)))
                        }
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(isSel ? 0 : 0.18), lineWidth: 1))
                        .contentShape(.contextMenuPreview, Capsule())
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            favorites.remove(place)
                        } label: {
                            Label("Retirer des favoris", systemImage: "star.slash")
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var placeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(selected.flag)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(Color.primary.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(selected.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                if !selected.subtitle.isEmpty {
                    Text(selected.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(selected.coordinateLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            Spacer(minLength: 8)

            if isActiveHere {
                LiveBadge()
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var actionButton: some View {
        let isActiveElsewhere = isActive && !isActiveHere

        let title: String = {
            if manager.isWorking { return isStopping ? "Retour à ta position…" : "Connexion…" }
            if isActiveHere { return "Arrêter la simulation" }
            if isActiveElsewhere { return "Téléporter ici" }
            return "Activer la position"
        }()
        let icon = isActiveHere ? "location.slash.fill" : "location.fill"
        let colors: [Color] = isActiveHere ? [Theme.danger, Theme.dangerDeep]
                                           : [Theme.accent, Theme.accentDeep]
        let glow = isActiveHere ? Theme.danger : Theme.accent
        let fg: Color = isActiveHere ? .white : Theme.onAccent

        return Button {
            Task { await toggle(isActiveHere: isActiveHere) }
        } label: {
            HStack(spacing: 10) {
                if manager.isWorking {
                    ProgressView().tint(fg)
                } else {
                    Image(systemName: icon)
                }
                Text(title).font(.headline)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                Capsule().fill(LinearGradient(colors: colors,
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
            .shadow(color: glow.opacity(0.45), radius: 18, y: 6)
            .contentTransition(.opacity)
        }
        .buttonStyle(PressableStyle())
        .disabled(manager.isWorking)
    }

    // MARK: Actions

    private static let homeID = "home"

    private var recenterButton: some View {
        Button { recenter() } label: {
            Image(systemName: "location.fill")
                .font(.headline)
                .foregroundStyle(Theme.me)
                .frame(width: 46, height: 46)
                .glass(radius: 23, interactive: true)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Revenir à ma position")
    }

    /// Recentre la carte sur la vraie position. Hors simulation, sélectionne aussi « Ma position ».
    private func recenter() {
        guard let real = realCoordinate else { return }
        searchFocused = false
        localError = nil
        if isActive {
            withAnimation(.smooth(duration: 0.9)) {
                position = .region(MKCoordinateRegion(
                    center: real, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
            }
        } else {
            hasChosen = false
            applyHome(at: real, focusMap: true)
        }
    }

    private static func initialPlace() -> Place {
        guard let c = UserLocationProvider.storedCoordinate() else { return Place.paris }
        return Place(id: homeID, name: "Ma position", subtitle: "Position réelle",
                     latitude: c.latitude, longitude: c.longitude)
    }

    /// Au lancement : si aucune simulation n'est en cours, relève la vraie position.
    private func startLocationTracking() async {
        let simulated = (try? await MacServerSimulator().isSimulationActive()) ?? false
        userLocation.isFrozen = simulated
        if !simulated { userLocation.refresh() }
    }

    /// Place « Ma position » (vraie position) comme lieu sélectionné.
    private func applyHome(at coordinate: CLLocationCoordinate2D, focusMap: Bool) {
        guard !isActive else { return }
        let wasHome = selected.id == Self.homeID
        guard wasHome || !hasChosen else { return }   // ne pas écraser un lieu choisi à la main
        let home = Place(id: Self.homeID, name: "Ma position",
                         subtitle: wasHome ? selected.subtitle : "Position réelle",
                         flag: wasHome ? selected.flag : Place.unknownFlag,
                         latitude: coordinate.latitude,
                         longitude: coordinate.longitude)
        selected = home
        if focusMap { focus(on: home) }
        Task { await enrichCountry(for: home) }
    }

    /// Après l'arrêt de la simulation : retour sur la vraie position.
    private func goHome() {
        guard let c = userLocation.location?.coordinate ?? UserLocationProvider.storedCoordinate() else { return }
        hasChosen = false
        applyHome(at: c, focusMap: true)
        // iOS met un instant à rendre la vraie position : on relève à nouveau juste après
        Task {
            try? await Task.sleep(for: .seconds(2))
            userLocation.refresh()
        }
    }

    private func choose(_ place: Place) {
        hasChosen = true
        localError = nil
        selected = place
        focus(on: place)
        // Lieu sans pays connu (point tapé sur la carte) : on cherche son drapeau
        Task { await enrichCountry(for: place) }
    }

    /// Complète le drapeau, le pays et le nom de ville d'un lieu à partir de ses coordonnées.
    private func enrichCountry(for place: Place) async {
        guard place.flag == Place.unknownFlag,
              let info = await search.country(at: place.coordinate) else { return }
        let isTappedPoint = place.name == "Point personnalisé"
        let updated = Place(id: place.id,
                            name: isTappedPoint ? (info.locality ?? place.name) : place.name,
                            subtitle: info.country.isEmpty ? place.subtitle : info.country,
                            flag: info.flag,
                            latitude: place.latitude,
                            longitude: place.longitude)
        if selected.id == place.id { selected = updated }
    }

    private func focus(on place: Place) {
        withAnimation(.smooth(duration: 0.9)) { position = .region(place.region) }
    }

    private func pick(_ suggestion: Suggestion) {
        searchFocused = false
        Task {
            do {
                let place = try await search.resolve(suggestion)
                search.clear()
                choose(place)
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    /// Appui long sur une suggestion : retire le lieu des favoris s'il y est déjà, sinon l'ajoute.
    private func toggleFavorite(_ suggestion: Suggestion) {
        if let existing = favorites.match(suggestion) {
            favorites.remove(existing)   // la recherche reste ouverte : l'étoile disparaît de la liste
            return
        }
        searchFocused = false
        Task {
            do {
                let place = try await search.resolve(suggestion)
                favorites.add(place)
                search.clear()   // referme la recherche : la barre de favoris réapparaît avec le nouveau lieu
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func toggle(isActiveHere: Bool) async {
        localError = nil
        isStopping = isActiveHere
        if isActiveHere {
            await manager.deactivate()
            if manager.activePlace == nil { goHome() }   // arrêt réussi
        } else {
            await enrichCountry(for: selected)   // le drapeau doit être connu avant l'activation
            await manager.activate(selected)
        }
        isStopping = false
    }
}

// MARK: - Composants

private extension Place {
    static let paris = Place.presets.last!
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate,
                           span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))
    }
}

private struct StatusChip: View {
    let state: LocationManager.State

    var body: some View {
        let (text, color): (String, Color) = switch state {
        case .idle: ("Inactif", .gray)
        case .working: ("Connexion…", Theme.accent)
        case .active: ("Position active", Theme.live)
        case .failed: ("Erreur", Theme.danger)
        }
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color, radius: 4)
            Text(text).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14).frame(height: 44)
        .glass(radius: 22)
        .contentTransition(.opacity)
    }
}

private struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.live).frame(width: 6, height: 6)
            Text("EN DIRECT")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
        }
        .foregroundStyle(Theme.live)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.live.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.live.opacity(0.35), lineWidth: 1))
    }
}

private struct ErrorPill: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.danger)
        .padding(12)
        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.danger.opacity(0.3), lineWidth: 1))
    }
}

private struct GhostPin: View {
    let isActive: Bool
    /// Pin « fusionné » avec ma position : anneau bleu + pastille bleue.
    var isMe = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = isActive ? Theme.live : Theme.accent
        ZStack {
            Circle()
                .stroke(color.opacity(0.7), lineWidth: 2)
                .frame(width: 46, height: 46)
                .scaleEffect(pulse ? 2.4 : 0.6)
                .opacity(pulse ? 0 : 0.9)
            Circle().fill(color)
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(isActive ? Color.white : Theme.onAccent, lineWidth: 3))
                .overlay(
                    GhostMark(color: isActive ? Theme.navy : Theme.onAccent)
                        .frame(width: 20, height: 20)
                )
                .shadow(color: color.opacity(0.8), radius: 10)

            if isMe {
                Circle().strokeBorder(Theme.me, lineWidth: 3)
                    .frame(width: 52, height: 52)
                Circle().fill(Theme.me)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: 18, y: 18)
            }
        }
        .animation(.smooth(duration: 0.3), value: isActive)
        .animation(.smooth(duration: 0.3), value: isMe)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Vraie position de l'iPhone : petit point bleu (différent du pin fantôme du lieu choisi).
private struct UserDot: View {
    var dimmed = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !dimmed {
                Circle()
                    .fill(Theme.me.opacity(0.28))
                    .frame(width: 40, height: 40)
                    .scaleEffect(pulse ? 1.8 : 0.7)
                    .opacity(pulse ? 0 : 0.9)
            }
            Circle().fill(Theme.me)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: Theme.me.opacity(0.6), radius: 6)
        }
        .opacity(dimmed ? 0.55 : 1)
        .animation(.smooth(duration: 0.3), value: dimmed)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager(backend: LoggingSimulator()))
        .environmentObject(PlaceSearchService())
        .preferredColorScheme(.dark)
}
