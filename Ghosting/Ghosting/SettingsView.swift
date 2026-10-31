import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = ServerDiscovery()

    @AppStorage(ServerConfig.hostKey) private var host = ServerConfig.defaultHost
    @AppStorage(ServerConfig.portKey) private var port = ServerConfig.defaultPort
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .french
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .dark
    @AppStorage(OnboardingState.key) private var onboardingDone = true

    @State private var test: TestState = .idle
    @FocusState private var focused: Field?

    private enum Field { case host, port }

    private enum TestState: Equatable {
        case idle, testing, success
        case failure(String)
    }

    private var portIsValid: Bool { ServerConfig.isValid(port: port) }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                discoverySection
                connectionSection
                languageSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background { backdrop }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { focused = nil }
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(appearance.colorScheme)
        .presentationDragIndicator(.visible)
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    // MARK: Fond

    private var backdrop: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.glow.opacity(0.4), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: Apparence

    private var appearanceSection: some View {
        Section {
            Picker("Apparence", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Apparence")
        }
        .listRowBackground(rowBackground)
    }

    // MARK: Détection automatique

    private var discoverySection: some View {
        Section {
            if discovery.servers.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Recherche d'un Mac Ghosting…")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(discovery.servers) { server in
                    DiscoveredServerRow(server: server,
                                        isSelected: host == server.host && port == server.port) {
                        host = server.host
                        port = server.port
                    }
                }
            }
        } header: {
            Text("Détection automatique")
        } footer: {
            Text("Ouvre Ghosting Server sur ton Mac (même réseau Wi-Fi) : il apparaît ici tout seul. Touche « Utiliser » pour remplir l'adresse et le port.")
        }
        .listRowBackground(rowBackground)
    }

    // MARK: Connexion

    private var connectionSection: some View {
        Section {
            LabeledContent("Adresse IP") {
                TextField(ServerConfig.defaultHost, text: $host)
                    .focused($focused, equals: .host)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focused = .port }
            }

            LabeledContent("Port") {
                TextField(String(ServerConfig.defaultPort),
                          value: $port, format: .number.grouping(.never))
                    .focused($focused, equals: .port)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .foregroundStyle(portIsValid ? Color.primary : Theme.danger)
            }

            Button {
                focused = nil
                Task { await runTest() }
            } label: {
                HStack {
                    Label("Tester la connexion", systemImage: "bolt.horizontal.fill")
                    Spacer()
                    if test == .testing { ProgressView() }
                }
            }
            .disabled(test == .testing || !portIsValid)

            testResult

            Button("Rétablir les valeurs par défaut", role: .destructive) {
                host = ServerConfig.defaultHost
                port = ServerConfig.defaultPort
                test = .idle
            }
        } header: {
            Text("Connexion au PC")
        } footer: {
            Text("Adresse IP locale du PC qui fait tourner le serveur Ghosting (même réseau Wi-Fi que l'iPhone) et son port. Le port par défaut est \(ServerConfig.defaultPort).")
        }
        .listRowBackground(rowBackground)
        .onChange(of: host) { test = .idle }
        .onChange(of: port) { test = .idle }
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
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(color)
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

    // MARK: Langue

    private var languageSection: some View {
        Section {
            Picker(selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text("\(lang.flag)  \(lang.label)").tag(lang)
                }
            } label: {
                Label("Langue", systemImage: "globe")
            }
        } header: {
            HStack {
                Text("Langue")
                Spacer()
                Text("EN COURS DE DÉVELOPPEMENT")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
        } footer: {
            Text("Le choix est enregistré, mais l'interface reste en français pour le moment.")
        }
        .listRowBackground(rowBackground)
    }

    // MARK: À propos

    private var aboutSection: some View {
        Section {
            VStack(spacing: 10) {
                GhostMark(color: Theme.accent)
                    .frame(width: 34, height: 34)
                    .frame(width: 68, height: 68)
                    .glass(radius: 22)
                Text("Ghosting")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("Propulsé par CrowStudios")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            LabeledContent("Version", value: version)

            Button {
                // Ferme les réglages et relance l'introduction
                dismiss()
                onboardingDone = false
            } label: {
                Label("Revoir l'introduction", systemImage: "sparkles")
            }

            if let url = URL(string: "https://discord.crowstudios.eu") {
                Link(destination: url) {
                    HStack {
                        Label("Serveur Discord", systemImage: "bubble.left.and.bubble.right.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Crédits")
        } footer: {
            Text("© 2026 CrowStudios. Tous droits réservés.")
        }
        .listRowBackground(rowBackground)
    }

    private var rowBackground: some View {
        Rectangle().fill(Color.primary.opacity(0.08))
    }
}

#Preview {
    SettingsView()
}
