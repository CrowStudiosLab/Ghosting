import SwiftUI

/// Introduction affichée une seule fois, au tout premier lancement.
struct OnboardingView: View {
    @StateObject private var discovery = ServerDiscovery()
    @AppStorage(OnboardingState.key) private var completed = false
    @AppStorage(ServerConfig.hostKey) private var host = ServerConfig.defaultHost
    @AppStorage(ServerConfig.portKey) private var port = ServerConfig.defaultPort
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .dark

    @State private var page = 0
    @State private var test: TestState = .idle
    @FocusState private var focused: Field?

    private enum Field { case host, port }
    private enum TestState: Equatable {
        case idle, testing, success
        case failure(String)
    }

    private let lastPage = 3
    private var portIsValid: Bool { ServerConfig.isValid(port: port) }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    howItWorksPage.tag(1)
                    serverPage.tag(2)
                    readyPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: page) { _, newPage in
                    focused = nil
                    // La recherche démarre ici (et pas avant) : iOS demande l'accès au réseau local à ce moment-là
                    if newPage == 2 { discovery.start() }
                }

                controls
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(appearance.colorScheme)
        .animation(.smooth(duration: 0.3), value: test)
        .onChange(of: discovery.servers) { _, servers in
            // Premier Mac trouvé et adresse jamais modifiée : on la remplit toute seule
            if let first = servers.first, host == ServerConfig.defaultHost {
                host = first.host
                port = first.port
            }
        }
        .onDisappear { discovery.stop() }
    }

    // MARK: Fond

    private var backdrop: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.glow.opacity(0.45), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.glow.opacity(0.28), .clear],
                           center: .bottom, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: Pages

    private var welcomePage: some View {
        pageLayout(icon: "ghost",
                   title: "Bienvenue sur Ghosting",
                   subtitle: "Change la position de ton iPhone en un tap, n'importe où dans le monde.") {
            Text("Propulsé par CrowStudios")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.accent.opacity(0.15), in: Capsule())
        }
    }

    private var howItWorksPage: some View {
        pageLayout(icon: "gearshape.2.fill",
                   title: "Comment ça marche",
                   subtitle: "Ghosting a besoin d'un PC pour modifier la position de l'iPhone.") {
            VStack(spacing: 0) {
                stepRow(icon: "laptopcomputer", title: "Un serveur sur ton PC",
                        text: "L'app envoie la position choisie au serveur Ghosting (server.py) qui tourne sur ton PC.")
                divider
                stepRow(icon: "cable.connector", title: "iPhone relié au PC",
                        text: "Branche ton iPhone et active le mode développeur (Réglages > Confidentialité et sécurité).")
                divider
                stepRow(icon: "wifi", title: "Même réseau Wi-Fi",
                        text: "L'iPhone et le PC doivent être connectés au même réseau pour se parler.")
            }
            .padding(.vertical, 6)
            .glass(radius: 24)
        }
    }

    private var serverPage: some View {
        pageLayout(icon: "server.rack",
                   title: "Configure le serveur",
                   subtitle: "Ghosting cherche ton Mac tout seul. Sinon, entre son adresse IP et le port du serveur.") {
            VStack(spacing: 12) {
                discoveryCard

                Text("Ou saisis l'adresse à la main")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    fieldRow("Adresse IP") {
                        TextField(ServerConfig.defaultHost, text: $host)
                            .focused($focused, equals: .host)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .onSubmit { focused = .port }
                    }
                    divider
                    fieldRow("Port") {
                        TextField(String(ServerConfig.defaultPort),
                                  value: $port, format: .number.grouping(.never))
                            .focused($focused, equals: .port)
                            .keyboardType(.numberPad)
                            .foregroundStyle(portIsValid ? Color.primary : Theme.danger)
                    }
                }
                .glass(radius: 22, interactive: true)

                Button {
                    focused = nil
                    Task { await runTest() }
                } label: {
                    HStack(spacing: 8) {
                        if test == .testing { ProgressView() }
                        else { Image(systemName: "bolt.horizontal.fill") }
                        Text("Tester la connexion").font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .glass(radius: 24, interactive: true)
                }
                .buttonStyle(PressableStyle())
                .disabled(test == .testing || !portIsValid)

                testResult

                Text("Sur le PC, l'IP locale s'affiche avec ipconfig (Windows) ou ifconfig (macOS/Linux). Au premier test, iOS te demandera l'accès au réseau local : accepte. Tu pourras tout modifier plus tard dans les réglages.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    /// Mac(s) Ghosting trouvés automatiquement sur le réseau.
    private var discoveryCard: some View {
        VStack(spacing: 0) {
            if discovery.servers.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Recherche de ton Mac…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
            } else {
                ForEach(discovery.servers) { server in
                    if server.id != discovery.servers.first?.id { divider }
                    DiscoveredServerRow(server: server,
                                        isSelected: host == server.host && port == server.port) {
                        host = server.host
                        port = server.port
                        test = .idle
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
        .glass(radius: 22)
        .animation(.smooth(duration: 0.3), value: discovery.servers)
    }

    private var readyPage: some View {
        pageLayout(icon: "checkmark.seal.fill",
                   title: "Tout est prêt",
                   subtitle: "Choisis l'apparence de l'app. Tu pourras la changer à tout moment dans les réglages.") {
            Picker("Apparence", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Briques

    private func pageLayout<Content: View>(icon: String, title: String, subtitle: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Group {
                    if icon == "ghost" {
                        GhostMark(color: Theme.accent).frame(width: 52, height: 52)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.accent)
                    }
                }
                    .frame(width: 104, height: 104)
                    .glass(radius: 34)
                    .padding(.top, 48)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                content().padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private func stepRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder field: () -> Content) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            field().multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var divider: some View {
        Divider().overlay(Color.primary.opacity(0.1)).padding(.leading, 16)
    }

    @ViewBuilder
    private var testResult: some View {
        if !portIsValid {
            resultRow("Port invalide (1 à 65535).", icon: "exclamationmark.triangle.fill", color: Theme.danger)
        } else {
            switch test {
            case .success:
                resultRow("Le PC répond.", icon: "checkmark.circle.fill", color: Theme.live)
            case .failure(let message):
                resultRow(message, icon: "xmark.octagon.fill", color: Theme.danger)
            case .idle, .testing:
                EmptyView()
            }
        }
    }

    private func resultRow(_ text: String, icon: String, color: Color) -> some View {
        Label {
            Text(text).font(.footnote).multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(color)
        .transition(.opacity)
    }

    // MARK: Navigation

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0...lastPage, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.accent : Color.primary.opacity(0.25))
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.smooth(duration: 0.3), value: page)

            Button(action: next) {
                Text(page == lastPage ? "Commencer" : "Continuer")
                    .font(.headline)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.45), radius: 18, y: 6)
            }
            .buttonStyle(PressableStyle())

            // Garde la hauteur stable pour éviter que le bouton principal saute d'une page à l'autre.
            Button(page == lastPage ? "Retour" : "Passer l'introduction") {
                if page == lastPage { goTo(page - 1) } else { finish() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(height: 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: 520)
    }

    private func next() {
        focused = nil
        if page == lastPage { finish() } else { goTo(page + 1) }
    }

    private func goTo(_ index: Int) {
        withAnimation(.smooth(duration: 0.4)) { page = index }
    }

    private func finish() {
        focused = nil
        withAnimation(.smooth(duration: 0.4)) { completed = true }
    }

    private func runTest() async {
        test = .testing
        do {
            try await MacServerSimulator().ping()
            test = .success
        } catch {
            test = .failure(error.localizedDescription)
        }
    }
}

#Preview {
    OnboardingView()
}
