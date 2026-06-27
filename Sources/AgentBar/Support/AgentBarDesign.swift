import SwiftUI

enum AgentBarDesign {
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 18
    static let appBackground = Color(red: 0.965, green: 0.972, blue: 0.984)
    static let cardBackground = Color.white.opacity(0.78)
    static let hairline = Color(red: 0.78, green: 0.84, blue: 0.93).opacity(0.55)
    static let durationFast = 0.15
    static let durationNormal = 0.20

    static func smoothAnimation(reduceMotion: Bool, duration: Double = durationNormal) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
}

private struct AgentBarPanelModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadowOpacity: Double = cornerRadius == 0 ? 0 : 1

        content
            .background(
                shape
                    .fill(cornerRadius == 0 ? AgentBarDesign.appBackground.opacity(0.72) : AgentBarDesign.cardBackground)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(alignment: .top) {
                        shape
                            .stroke(.white.opacity(cornerRadius == 0 ? 0 : 0.72), lineWidth: 1)
                            .blur(radius: 0.4)
                    }
            )
            .overlay {
                shape.strokeBorder(AgentBarDesign.hairline, lineWidth: 0.8)
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
