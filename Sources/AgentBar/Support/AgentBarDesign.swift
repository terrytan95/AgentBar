import SwiftUI
import CoreText

enum AgentBarDesign {
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 18
    static let appBackground = adaptiveColor(
        light: NSColor.windowBackgroundColor,
        dark: NSColor(calibratedRed: 0.060, green: 0.064, blue: 0.058, alpha: 1)
    )
    static let cardBackground = adaptiveColor(
        light: NSColor.controlBackgroundColor.withAlphaComponent(0.78),
        dark: NSColor(calibratedRed: 0.165, green: 0.170, blue: 0.155, alpha: 0.78)
    )
    static let hairline = adaptiveColor(
        light: NSColor.separatorColor.withAlphaComponent(0.72),
        dark: NSColor(calibratedWhite: 1, alpha: 0.13)
    )
    static let panelHighlight = adaptiveColor(
        light: NSColor.controlBackgroundColor.withAlphaComponent(0.72),
        dark: NSColor(calibratedWhite: 1, alpha: 0.075)
    )
    static let panelGlow = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.28),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let durationFast = 0.15
    static let durationNormal = 0.20

    static func smoothAnimation(reduceMotion: Bool, duration: Double = durationNormal) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum AgentBarFonts {
    static let ui = "IBM Plex Sans"
    static let mono = "IBM Plex Mono"
    static let display = "Space Grotesk"

    static func registerIfNeeded() {
        _ = registered
    }

    private static let registered: Void = {
        [
            "IBMPlexSans-Regular",
            "IBMPlexSans-Medium",
            "IBMPlexSans-SemiBold",
            "IBMPlexSans-Bold",
            "IBMPlexMono-Regular",
            "IBMPlexMono-Medium",
            "IBMPlexMono-SemiBold",
            "IBMPlexMono-Bold",
            "SpaceGrotesk[wght]"
        ].forEach { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                NSLog("AgentBar font missing: \(name)")
                return
            }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

extension Font {
    static func agentBar(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AgentBarFonts.registerIfNeeded()
        return .custom(AgentBarFonts.ui, size: size).weight(weight)
    }

    static func agentBarMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AgentBarFonts.registerIfNeeded()
        return .custom(AgentBarFonts.mono, size: size).weight(weight)
    }

    static func agentBarDisplay(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AgentBarFonts.registerIfNeeded()
        return .custom(AgentBarFonts.display, size: size).weight(weight)
    }
}

private struct AgentBarPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if colorScheme == .dark {
            darkBody(content: content)
        } else {
            lightBody(content: content)
        }
    }

    private func darkBody(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadowOpacity: Double = cornerRadius == 0 ? 0 : 1

        return content
            .background {
                shape
                    .fill(.regularMaterial)
                    .opacity(cornerRadius == 0 ? 0 : 1)
                    .overlay {
                        shape.fill(cornerRadius == 0 ? AgentBarDesign.appBackground.opacity(0.72) : AgentBarDesign.cardBackground)
                    }
                    .overlay(alignment: .top) {
                        shape
                            .stroke(AgentBarDesign.panelGlow.opacity(cornerRadius == 0 ? 0 : 0.95), lineWidth: 1)
                            .blur(radius: 0.4)
                    }
            }
            .overlay {
                shape.strokeBorder(AgentBarDesign.hairline, lineWidth: 0.8)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.14 * shadowOpacity), radius: 24, y: 12)
            .shadow(color: .black.opacity(0.05 * shadowOpacity), radius: 4, y: 1)
    }

    private func lightBody(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadowOpacity: Double = cornerRadius == 0 ? 0 : 1

        return content
            .background(
                shape
                    .fill(cornerRadius == 0 ? Color(nsColor: .windowBackgroundColor).opacity(0.72) : Color(nsColor: .controlBackgroundColor).opacity(0.78))
                    .overlay(alignment: .top) {
                        shape
                            .stroke(Color(nsColor: .controlBackgroundColor).opacity(cornerRadius == 0 ? 0 : 0.72), lineWidth: 1)
                            .blur(radius: 0.4)
                    }
            )
            .overlay {
                shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.8)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.07 * shadowOpacity), radius: 16, y: 8)
            .shadow(color: .black.opacity(0.035 * shadowOpacity), radius: 3, y: 1)
    }
}

private struct AgentBarPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(
                AgentBarDesign.smoothAnimation(reduceMotion: reduceMotion, duration: AgentBarDesign.durationFast),
                value: configuration.isPressed
            )
    }
}

extension View {
    func agentBarPanel(cornerRadius: CGFloat = AgentBarDesign.radiusMedium) -> some View {
        modifier(AgentBarPanelModifier(cornerRadius: cornerRadius))
    }

    func tactilePlainButton(enabled isEnabled: Bool = true) -> some View {
        buttonStyle(AgentBarPressButtonStyle())
            .pointingHandCursor(enabled: isEnabled)
    }
}
