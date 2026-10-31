import SwiftUI
import AppKit

/// Fenêtre unique : état du serveur, iPhone branché ou non, adresse à saisir dans l'app iPhone.
struct ContentView: View {
    @EnvironmentObject private var server: ServerProcess
    @EnvironmentObject private var monitor: DeviceMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSettings = false
    @State private var copied = false
    @State private var float = false
    @State private var pulse = false

    // MARK: Phase

    private enum Phase {
        case stopped
        case starting
        case failed(String)
        case waitingPhone
        case ready(String)
        case simulating(ServerStatus)
    }

    private var phase: Phase {
        switch server.state {
        case .stopped, .stopping: return .stopped
        case .starting: return .starting
        case .failed(let message): return .failed(message)
        case .running:
            if let sim = monitor.simulation, sim.active { return .simulating(sim) }
            if case .connected(let name) = monitor.phone { return .ready(name) }
            if case .wireless(let name) = monitor.phone { return .ready(name) }
            return .waitingPhone
        }
    }

    private var isLive: Bool {
        switch phase {
        case .ready, .simulating: true
        default: false
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .ready, .simulating: Theme.live
        case .failed: Theme.danger
        case .stopped: .gray
        case .starting, .waitingPhone: Theme.accent
        }
    }

    private var title: String {
        switch phase {
        case .stopped: "Serveur arrêté"
        case .starting: "Démarrage…"
        case .failed: "Serveur en erreur"
        case .waitingPhone: "Branche ton iPhone"
        case .ready: "Prêt"
        case .simulating: "Position active"
        }
    }

    private var subtitle: String {
        switch phase {
        case .stopped: "Démarre le serveur pour que l'app Ghosting de ton iPhone puisse s'y connecter."
        case .starting: "Le serveur se prépare, quelques secondes."
        case .failed(let message): message
        case .waitingPhone: "Relie-le en USB à ce Mac, déverrouille-le, puis touche « Faire confiance »."
        case .ready(let name): "\(name) est connecté. Ouvre Ghosting sur ton iPhone et choisis une position."
        case .simulating(let sim): sim.coordinateLabel.map { "Ton iPhone est simulé en \($0)" } ?? "Ton iPhone est en position simulée."
        }
    }

    // MARK: Corps

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 22) {
                topBar
                hero
                stepsCard
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 22)
            // La barre de titre est masquée : on remonte le contenu à la hauteur des boutons rouge/jaune/gris
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(width: 520, height: 700)
        .tint(Theme.accent)
        .animation(.smooth(duration: 0.4), value: server.state)
        .animation(.smooth(duration: 0.4), value: monitor.phone)
        .animation(.smooth(duration: 0.4), value: monitor.simulation)
        .animation(.smooth(duration: 0.3), value: showSettings)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { pulse = true }
        }
        .overlay {
            if showSettings {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { showSettings = false }
                    SettingsView(onClose: { showSettings = false })
                        .environmentObject(server)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.glow.opacity(0.45), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [(isLive ? Theme.live : Theme.glow).opacity(0.38), .clear],
                           center: .bottom, startRadius: 0, endRadius: 500)
        }
        .animation(.smooth(duration: 0.6), value: isLive)
        .ignoresSafeArea()
    }

    // MARK: Barre du haut

    private var topBar: some View {
        ZStack {
            HStack {
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 38, height: 38)
                        .glass(radius: 19, interactive: true)
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("Réglages")
            }
        }
        .frame(height: 38)
        .padding(.trailing, -6)    // engrenage un peu plus à droite
        .padding(.bottom, 34)      // redescend le titre et les étapes
    }

    // MARK: Fantôme + message

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(phaseColor.opacity(0.7), lineWidth: 2)
                    .frame(width: 124, height: 124)
                    .scaleEffect(pulse ? 1.9 : 0.85)
                    .opacity(pulse ? 0 : 0.9)

                GhostMark(color: isLive ? Theme.live : Theme.accent)
                    .frame(width: 60, height: 60)
                    .frame(width: 124, height: 124)
                    .glass(radius: 62, tint: phaseColor)
                    .offset(y: float ? -6 : 6)
                    .shadow(color: phaseColor.opacity(0.45), radius: 24, y: 10)
            }
            .frame(height: 160)
            .offset(y: -16)        // remonte seulement le fantôme

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .contentTransition(.opacity)
            }
        }
    }

    // MARK: Étapes

    private enum StepState { case done, working, waiting, error }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            stepRow(icon: "bolt.fill", title: "Serveur",
                    detail: serverDetail, state: serverStep) { EmptyView() }
            divider
            stepRow(icon: "iphone", title: "iPhone",
                    detail: phoneDetail, state: phoneStep) { EmptyView() }
            divider
            stepRow(icon: "wifi", title: "Adresse pour l'app iPhone",
                    detail: addressDetail, state: addressStep) {
                if let ip = monitor.localIP {
                    Button { copy(ip) } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copier l'adresse IP")
                }
            }
        }
        .padding(.vertical, 6)
        .glass(radius: 24)
    }

    private var serverStep: StepState {
        switch server.state {
        case .running: .done
        case .starting, .stopping: .working
        case .stopped: .waiting
        case .failed: .error
        }
    }

    private var serverDetail: String {
        switch server.state {
        case .running: "En marche sur le port \(ServerConfig.port)"
        case .starting: "Démarrage…"
        case .stopping: "Arrêt…"
        case .stopped: "Arrêté"
        case .failed: "Erreur, voir les réglages"
        }
    }

    private var phoneStep: StepState {
        switch monitor.phone {
        case .connected, .wireless: return .done
        case .disconnected, .unknown: return .waiting
        }
    }

    private var phoneDetail: String {
        switch monitor.phone {
        case .connected(let name): "\(name) · USB"
        case .wireless(let name): "\(name) · Wi-Fi"
        case .disconnected: "Aucun iPhone détecté"
        case .unknown: "Recherche d'un iPhone…"
        }
    }

    private var addressStep: StepState { monitor.localIP == nil ? .waiting : .done }

    private var addressDetail: String {
        if let ip = monitor.localIP { return "\(ip)  ·  port \(ServerConfig.port)" }
        return "Mac non connecté au Wi-Fi"
    }

    private func stepRow<Trailing: View>(icon: String, title: String, detail: String, state: StepState,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(stepColor(state).opacity(0.16))
                switch state {
                case .done:
                    Image(systemName: "checkmark").font(.footnote.weight(.bold))
                case .error:
                    Image(systemName: "xmark").font(.footnote.weight(.bold))
                case .working:
                    ProgressView().controlSize(.small)
                case .waiting:
                    Image(systemName: icon).font(.footnote.weight(.semibold))
                }
            }
            .foregroundStyle(stepColor(state))
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func stepColor(_ state: StepState) -> Color {
        switch state {
        case .done: Theme.live
        case .error: Theme.danger
        case .working: Theme.accent
        case .waiting: .secondary
        }
    }

    private var divider: some View {
        Divider().overlay(Color.primary.opacity(0.1)).padding(.leading, 66)
    }

    // MARK: Boutons

    private var footer: some View {
        VStack(spacing: 12) {
            if case .simulating = phase {
                Button {
                    Task { try? await LocalServerClient().stop() }
                } label: {
                    Label("Rétablir la vraie position", systemImage: "location.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .glass(radius: 22, interactive: true)
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }

            mainButton

            Text("Propulsé par CrowStudios")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var mainButton: some View {
        let running = server.state == .running
        let busy = server.state == .starting || server.state == .stopping

        let title: String = {
            switch server.state {
            case .starting: return "Démarrage…"
            case .stopping: return "Arrêt…"
            case .running: return "Arrêter le serveur"
            case .stopped, .failed: return "Démarrer le serveur"
            }
        }()
        let icon = running ? "stop.fill" : "play.fill"
        let colors: [Color] = running ? [Theme.danger, Theme.dangerDeep] : [Theme.accent, Theme.accentDeep]
        let fg: Color = running ? .white : Theme.onAccent
        let glow = running ? Theme.danger : Theme.accent

        return Button {
            Task {
                if running { await server.stop() } else { await server.restart() }
            }
        } label: {
            HStack(spacing: 10) {
                if busy { ProgressView().controlSize(.small).tint(fg) } else { Image(systemName: icon) }
                Text(title).font(.headline)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background {
                Capsule().fill(LinearGradient(colors: colors,
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
            .shadow(color: glow.opacity(0.45), radius: 18, y: 6)
            .contentTransition(.opacity)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
