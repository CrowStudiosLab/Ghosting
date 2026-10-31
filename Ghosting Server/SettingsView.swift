import SwiftUI
import AppKit

struct SettingsView: View {
    var onClose: () -> Void

    @EnvironmentObject private var server: ServerProcess

    @AppStorage(ServerConfig.portKey) private var port = ServerConfig.defaultPort
    @AppStorage(ServerConfig.pythonPathKey) private var pythonPath = ""
    @AppStorage(ServerConfig.udidKey) private var udid = ""
    @AppStorage(ServerConfig.tokenKey) private var token = ""
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .dark
    @AppStorage(OnboardingState.key) private var onboardingDone = true

    @State private var portText = ""
    @State private var showLog = false
    @Namespace private var pickerNamespace

    private var portIsValid: Bool {
        Int(portText).map { ServerConfig.isValid(port: $0) } ?? false
    }
    private var serverIsBusy: Bool { server.state == .starting || server.state == .stopping }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: Corps

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 22) {
                    section("Apparence") { appearancePicker }

                    section("Serveur",
                            footer: "Redémarre le serveur après avoir modifié le port, Python, l'UDID ou le jeton. Si tu définis un jeton, renseigne le même dans l'app iPhone (MacServerSimulator.token).") {
                        serverRows
                    }

                    section("Crédits", footer: "© 2026 CrowStudios. Tous droits réservés.") {
                        creditsRows
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 440, height: 620)
        .background(Theme.background.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .glass(radius: 32)
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
        .onExitCommand(perform: onClose)
        .onAppear { portText = String(ServerConfig.port) }
    }

    // MARK: En-tête

    private var header: some View {
        HStack {
            Text("Réglages")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Spacer()
            Button(action: onClose) {
                Text("OK")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 32)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: Apparence

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

    // MARK: Serveur

    private var serverRows: some View {
        VStack(spacing: 0) {
            row("État") { ServerStateBadge(state: server.state) }
            rowDivider

            row("Port") {
                TextField("", text: $portText, prompt: Text(String(ServerConfig.defaultPort)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(portIsValid ? Color.primary : Theme.danger)
                    .frame(width: 90)
                    .onChange(of: portText) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(5))
                        if digits != newValue { portText = digits; return }
                        if let value = Int(digits), ServerConfig.isValid(port: value) { port = value }
                    }
            }
            rowDivider

            row("Python") {
                HStack(spacing: 8) {
                    TextField("", text: $pythonPath, prompt: Text("Venv Ghosting (défaut)"))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .autocorrectionDisabled()
                    Button {
                        if let path = PythonPicker.choose() { pythonPath = path }
                    } label: {
                        Text("Choisir…")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Color.primary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            rowDivider

            row("UDID iPhone") {
                TextField("", text: $udid, prompt: Text("Optionnel"))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .autocorrectionDisabled()
            }
            rowDivider

            row("Jeton") {
                TextField("", text: $token, prompt: Text("Optionnel"))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .autocorrectionDisabled()
            }
            rowDivider

            Button {
                Task { await server.restart() }
            } label: {
                row("Redémarrer le serveur", icon: "arrow.clockwise") {
                    if serverIsBusy { ProgressView().controlSize(.small) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(serverIsBusy || !portIsValid)
            .opacity(serverIsBusy || !portIsValid ? 0.5 : 1)

            if !portIsValid {
                rowDivider
                resultRow("Port invalide (1 à 65535).", icon: "exclamationmark.triangle.fill")
            }
            if case .failed(let message) = server.state {
                rowDivider
                resultRow(message, icon: "xmark.octagon.fill")
            }
            rowDivider

            logRow
            rowDivider

            Button(role: .destructive) {
                port = ServerConfig.defaultPort
                portText = String(ServerConfig.defaultPort)
                pythonPath = ""
                udid = ""
                token = ""
            } label: {
                row("Rétablir les valeurs par défaut", icon: "arrow.uturn.backward", tint: Theme.danger) {}
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private var logRow: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { showLog.toggle() }
            } label: {
                row("Journal du serveur", icon: "text.alignleft") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showLog ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showLog {
                ScrollView {
                    Text(server.logText.isEmpty ? "Aucune sortie pour le moment." : server.logText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 150)
                .background(Color.black.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    // MARK: Crédits

    private var creditsRows: some View {
        VStack(spacing: 0) {
            row("Version") {
                Text(version)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            rowDivider
            Button {
                // Ferme les réglages et relance l'introduction
                onClose()
                onboardingDone = false
            } label: {
                row("Revoir l'introduction", icon: "sparkles") {}
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let url = URL(string: "https://discord.crowstudios.eu") {
                rowDivider
                Link(destination: url) {
                    row("Serveur Discord", icon: "bubble.left.and.bubble.right.fill") {
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    // MARK: Briques

    private func section<Content: View>(_ title: String, footer: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            content()
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func row<Trailing: View>(_ title: String, icon: String? = nil, tint: Color? = nil,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint ?? Theme.accent)
                    .frame(width: 20)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(tint ?? Color.primary)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }

    private func resultRow(_ text: String, icon: String) -> some View {
        Label {
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(Theme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rowDivider: some View {
        Divider().overlay(Color.primary.opacity(0.08)).padding(.leading, 14)
    }
}

private extension View {
    /// Carte arrondie à fond léger (posée sur la surface glass des réglages).
    func card() -> some View {
        self
            .background(Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
