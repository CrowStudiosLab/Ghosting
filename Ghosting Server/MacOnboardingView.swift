import SwiftUI
import AppKit

enum OnboardingState {
    /// Passe à `true` quand l'introduction est terminée ou passée.
    static let key = "onboarding.completed"
}

/// Introduction de Ghosting Server : explications, recherche de Python, installation des dépendances (si besoin).
struct MacOnboardingView: View {
    @EnvironmentObject private var server: ServerProcess
    @AppStorage(OnboardingState.key) private var completed = false
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .dark

    @StateObject private var setup = PythonSetup()
    @Namespace private var pickerNamespace

    private enum Page: Hashable { case welcome, how, python, dependencies, ready }

    @State private var page: Page = .welcome
    @State private var goingForward = true
    /// La page « dépendances » n'existe que si le Python choisi en a besoin.
    @State private var dependenciesRequired = false
    @State private var showLog = false
    /// Python configuré à l'ouverture : si on le change, le serveur est relancé à la fin.
    @State private var initialPython = ServerConfig.pythonPath

    private var pages: [Page] {
        dependenciesRequired ? [.welcome, .how, .python, .dependencies, .ready]
                             : [.welcome, .how, .python, .ready]
    }
    private var index: Int { pages.firstIndex(of: page) ?? 0 }
    private var isInstalling: Bool { setup.installState == .installing }

    // MARK: Corps

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                ZStack {
                    pageView
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)))
                }
                .clipped()

                controls
            }
        }
        .frame(width: 520, height: 700)
        .tint(Theme.accent)
        .task { setup.scan() }
    }

    private var backdrop: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.glow.opacity(0.45), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.glow.opacity(0.28), .clear],
                           center: .bottom, startRadius: 0, endRadius: 500)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var pageView: some View {
        switch page {
        case .welcome: welcomePage
        case .how: howItWorksPage
        case .python: pythonPage
        case .dependencies: dependenciesPage
        case .ready: readyPage
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        pageLayout(icon: "ghost",
                   title: "Bienvenue dans Ghosting Server",
                   subtitle: "Ce serveur relie l'app Ghosting de ton iPhone à ton Mac pour changer ta position.") {
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
                   subtitle: "Une courte préparation, une seule fois.") {
            VStack(spacing: 0) {
                stepRow(icon: "bolt.fill", title: "Un serveur sur ton Mac",
                        text: "Ghosting Server lance server.py, qui parle à ton iPhone grâce à Python et pymobiledevice3.")
                divider
                stepRow(icon: "cable.connector", title: "iPhone relié en USB",
                        text: "Branche-le, déverrouille-le, touche « Faire confiance » et active le mode développeur (Réglages > Confidentialité et sécurité).")
                divider
                stepRow(icon: "wifi", title: "Même réseau Wi-Fi",
                        text: "L'app iPhone retrouve ton Mac automatiquement sur le réseau local.")
            }
            .padding(.vertical, 6)
            .glass(radius: 24)
        }
    }

    // MARK: Python

    private var pythonPage: some View {
        pageLayout(icon: "terminal.fill",
                   title: "Où est Python ?",
                   subtitle: "Ghosting Server a besoin de Python 3.\(PythonProbe.minimumMinor) ou plus récent. Je le cherche pour toi.") {
            VStack(spacing: 14) {
                pythonCard

                HStack(spacing: 10) {
                    actionButton("Chercher à nouveau", icon: "arrow.clockwise") { setup.scan(force: true) }
                        .disabled(setup.isScanning || setup.isChecking)
                    actionButton("Choisir…", icon: "folder") { Task { await setup.pickManually() } }
                        .disabled(setup.isChecking)
                }

                if let message = setup.invalidMessage {
                    resultRow(message, icon: "xmark.octagon.fill", color: Theme.danger)
                }

                Text("Pas de Python ? Installe-le avec `brew install python`, puis touche « Chercher à nouveau ».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
    }

    private var pythonCard: some View {
        VStack(spacing: 0) {
            if setup.candidates.isEmpty {
                HStack(spacing: 14) {
                    if setup.isScanning || setup.isChecking {
                        ProgressView().controlSize(.small).frame(width: 36)
                        Text("Recherche de Python…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.danger)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aucun Python trouvé").font(.subheadline.weight(.semibold))
                            Text("Installe-le ou choisis-le à la main.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            } else {
                ForEach(setup.candidates) { candidate in
                    if candidate.id != setup.candidates.first?.id { divider }
                    pythonRow(candidate)
                }
            }
        }
        .padding(.vertical, setup.candidates.isEmpty ? 0 : 4)
        .glass(radius: 24)
        .animation(.smooth(duration: 0.3), value: setup.candidates)
    }

    private func pythonRow(_ candidate: PythonCandidate) -> some View {
        let isSelected = setup.selected?.path == candidate.path
        return Button { setup.choose(candidate) } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.live : Color.secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Python \(candidate.version)").font(.subheadline.weight(.semibold))
                    Text(candidate.displayPath)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(candidate.hasDeps ? "Prêt" : "À compléter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(candidate.hasDeps ? Theme.live : Color.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background((candidate.hasDeps ? Theme.live : Color.secondary).opacity(0.15), in: Capsule())
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Dépendances

    private var dependenciesPage: some View {
        pageLayout(icon: "shippingbox.fill",
                   title: "Installe les dépendances",
                   subtitle: "Il manque deux modules Python pour que le serveur fonctionne.") {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    packageRow("flask", "Le mini serveur web que l'iPhone appelle")
                    divider
                    packageRow("pymobiledevice3", "Le dialogue avec l'iPhone en USB")
                }
                .padding(.vertical, 6)
                .glass(radius: 24)

                installStatus

                logSection

                if let python = setup.selected, !PythonProbe.isVirtualEnv(python.path) {
                    Text("Un environnement dédié est créé dans ~/Library/Application Support/Ghosting Server : ton Python n'est pas modifié.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func packageRow(_ name: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(installColor.opacity(0.16))
                switch setup.installState {
                case .installing:
                    ProgressView().controlSize(.small)
                case .success:
                    Image(systemName: "checkmark").font(.footnote.weight(.bold))
                case .failure:
                    Image(systemName: "xmark").font(.footnote.weight(.bold))
                case .idle:
                    Image(systemName: "arrow.down").font(.footnote.weight(.semibold))
                }
            }
            .foregroundStyle(installColor)
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(.subheadline, design: .monospaced, weight: .semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private var installColor: Color {
        switch setup.installState {
        case .idle: .secondary
        case .installing: Theme.accent
        case .success: Theme.live
        case .failure: Theme.danger
        }
    }

    @ViewBuilder
    private var installStatus: some View {
        switch setup.installState {
        case .idle:
            EmptyView()
        case .installing:
            Text(setup.installLog.last ?? "Préparation…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        case .success:
            resultRow("Dépendances installées.", icon: "checkmark.circle.fill", color: Theme.live)
        case .failure(let message):
            resultRow(message, icon: "xmark.octagon.fill", color: Theme.danger)
        }
    }

    @ViewBuilder
    private var logSection: some View {
        if !setup.installLog.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.smooth(duration: 0.25)) { showLog.toggle() }
                } label: {
                    HStack {
                        Text("Détails").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showLog ? 90 : 0))
                    }
                    .padding(.horizontal, 16).frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showLog {
                    ScrollView {
                        Text(setup.installLog.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 150)
                    .background(Color.black.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
            .glass(radius: 22)
        }
    }

    // MARK: Fin

    private var readyPage: some View {
        pageLayout(icon: "checkmark.seal.fill",
                   title: "Tout est prêt",
                   subtitle: "Choisis l'apparence. Tu pourras la changer à tout moment dans les réglages.") {
            VStack(spacing: 16) {
                if let python = setup.selected {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.live)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Python \(python.version)").font(.subheadline.weight(.semibold))
                            Text(python.displayPath)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glass(radius: 22)
                }
                appearancePicker
            }
        }
    }

    private var appearancePicker: some View {
        HStack(spacing: 4) {
            ForEach(AppAppearance.allCases) { option in
                let selected = appearance == option
                Button {
                    withAnimation(.smooth(duration: 0.25)) { appearance = option }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Theme.onAccent : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if selected {
                                Capsule().fill(Theme.accent)
                                    .matchedGeometryEffect(id: "selection", in: pickerNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.07), in: Capsule())
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
                .padding(.top, 36)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content().padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func stepRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .glass(radius: 22, interactive: true)
        }
        .buttonStyle(PressableStyle())
    }

    private func resultRow(_ text: String, icon: String, color: Color) -> some View {
        Label {
            Text(text).font(.footnote).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(color)
        .transition(.opacity)
    }

    private var divider: some View {
        Divider().overlay(Color.primary.opacity(0.1)).padding(.leading, 66)
    }

    // MARK: Navigation

    private var primaryTitle: String {
        switch page {
        case .welcome, .how: "Continuer"
        case .python: setup.isScanning ? "Recherche…" : "Continuer"
        case .dependencies:
            switch setup.installState {
            case .idle: "Installer"
            case .installing: "Installation…"
            case .failure: "Réessayer"
            case .success: "Continuer"
            }
        case .ready: "Démarrer le serveur"
        }
    }

    private var primaryDisabled: Bool {
        switch page {
        case .python: setup.selected == nil || setup.isScanning || setup.isChecking
        case .dependencies: isInstalling
        default: false
        }
    }

    private var secondaryTitle: String {
        switch page {
        case .welcome, .how: "Passer l'introduction"
        default: "Retour"
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Theme.accent : Color.primary.opacity(0.25))
                        .frame(width: i == index ? 22 : 8, height: 8)
                }
            }
            .animation(.smooth(duration: 0.3), value: page)
            .animation(.smooth(duration: 0.3), value: dependenciesRequired)

            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    if isInstalling { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                    Text(primaryTitle).font(.headline)
                }
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .shadow(color: Theme.accent.opacity(0.45), radius: 18, y: 6)
                .contentTransition(.opacity)
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(primaryDisabled)
            .opacity(primaryDisabled && !isInstalling ? 0.55 : 1)

            Button(secondaryTitle, action: secondaryAction)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 24)
                .disabled(isInstalling)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private func primaryAction() {
        switch page {
        case .welcome:
            go(to: .how)
        case .how:
            go(to: .python)
        case .python:
            // La page des dépendances n'apparaît que si le Python choisi en a besoin
            let needsDependencies = !(setup.selected?.hasDeps ?? true)
            dependenciesRequired = needsDependencies
            go(to: needsDependencies ? .dependencies : .ready)
        case .dependencies:
            if setup.installState == .success { go(to: .ready) }
            else { Task { await setup.install() } }
        case .ready:
            finish()
        }
    }

    private func secondaryAction() {
        if page == .welcome || page == .how { finish(); return }
        guard index > 0 else { return }
        go(to: pages[index - 1])
    }

    private func go(to target: Page) {
        goingForward = (pages.firstIndex(of: target) ?? 0) > index
        withAnimation(.smooth(duration: 0.4)) { page = target }
    }

    private func finish() {
        let pythonChanged = ServerConfig.pythonPath != initialPython
        withAnimation(.smooth(duration: 0.4)) { completed = true }
        Task {
            // Python changé : on relance. Sinon, premier lancement : on démarre simplement.
            if pythonChanged { await server.restart() } else { await server.start() }
        }
    }
}
