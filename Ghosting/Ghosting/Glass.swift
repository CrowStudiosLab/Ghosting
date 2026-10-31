import SwiftUI
import UIKit

// MARK: - Tokens

enum Theme {
    // Palette de l'icône : bleu nuit + blanc
    static let navy = Color(hex: "1F2850")
    static let navySoft = Color(hex: "4B5272")

    /// Couleur principale : bleu nuit en mode clair, blanc bleuté en mode sombre.
    static let accent = Color.adaptive(light: "1F2850", dark: "F2F4FF")
    static let accentDeep = Color.adaptive(light: "4B5272", dark: "C5CBEA")
    /// Texte / icône posés SUR l'accent (boutons, puces sélectionnées, pin).
    static let onAccent = Color.adaptive(light: "FFFFFF", dark: "1F2850")
    /// Fond des écrans plein (réglages, introduction).
    static let background = Color.adaptive(light: "F6F7FB", dark: "0A0F20")
    /// Halo d'ambiance (dégradés radiaux).
    static let glow = Color.adaptive(light: "AEB8EE", dark: "4A5BB8")

    /// Bleu « ma position » (vraie position de l'iPhone)
    static let me = Color(hex: "2F8BFF")
    static let live = Color(hex: "3DFFA2")
    static let danger = Color(hex: "FF5C6C")
    static let dangerDeep = Color(hex: "E0364A")
}

// MARK: - Liquid Glass (natif iOS 26, fallback matériau + reflets avant)

struct GlassSurface: ViewModifier {
    var radius: CGFloat = 28
    var tint: Color? = nil
    var interactive = false

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            let base: Glass = tint.map { Glass.regular.tint($0.opacity(0.4)) } ?? .regular
            content.glassEffect(interactive ? base.interactive() : base,
                                in: .rect(cornerRadius: radius))
        } else {
            content
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.ultraThinMaterial)
                        if let tint {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(tint.opacity(0.28))
                        }
                        // reflet de lumière en haut à gauche
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                                 startPoint: .topLeading, endPoint: .center))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.65), .white.opacity(0.08), .white.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
    }
}

extension View {
    func glass(radius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(radius: radius, tint: tint, interactive: interactive))
    }
}

/// Retour tactile « ressort » sur pression.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Utilitaires

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        self.init(red: Double((value & 0xFF0000) >> 16) / 255,
                  green: Double((value & 0x00FF00) >> 8) / 255,
                  blue: Double(value & 0x0000FF) / 255)
    }
}

extension Color {
    /// Couleur qui suit le mode clair / sombre (hex sans « # »).
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(hexString: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    nonisolated convenience init(hexString: String) {
        let clean = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        self.init(red: CGFloat((value & 0xFF0000) >> 16) / 255,
                  green: CGFloat((value & 0x00FF00) >> 8) / 255,
                  blue: CGFloat(value & 0x0000FF) / 255,
                  alpha: 1)
    }
}

// MARK: - Fantôme (dessiné comme sur l'icône : contour + deux yeux)

struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let r = w / 2
        let base = h * 0.86          // début des vagues
        let amp = h * 0.14           // profondeur des vagues

        // Dôme : demi-cercle de gauche à droite en passant par le haut (y vers le bas)
        let steps = 90
        for i in 0...steps {
            let angle = Double.pi + Double.pi * Double(i) / Double(steps)
            let point = CGPoint(x: rect.minX + r + r * CGFloat(cos(angle)),
                                y: rect.minY + r + r * CGFloat(sin(angle)))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        // Côté droit, puis trois vagues de droite à gauche
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + base))
        let seg = w / 3
        for i in 0..<3 {
            let xStart = rect.maxX - seg * CGFloat(i)
            let xEnd = xStart - seg
            p.addQuadCurve(to: CGPoint(x: xEnd, y: rect.minY + base),
                           control: CGPoint(x: (xStart + xEnd) / 2, y: rect.minY + base + amp * 2))
        }
        p.closeSubpath()
        return p
    }
}

struct GhostMark: View {
    var color: Color = Theme.navy

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let line = s * 0.13
            ZStack {
                GhostShape()
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                    .padding(line / 2)
                Ellipse().fill(color)
                    .frame(width: s * 0.1, height: s * 0.15)
                    .position(x: s * 0.35, y: s * 0.42)
                Ellipse().fill(color)
                    .frame(width: s * 0.1, height: s * 0.15)
                    .position(x: s * 0.65, y: s * 0.42)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
