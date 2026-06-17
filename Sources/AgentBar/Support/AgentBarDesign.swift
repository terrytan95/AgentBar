import SwiftUI

enum AgentBarDesign {
    static let radiusMedium: CGFloat = 12
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
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
                    .background(.regularMaterial, in: shape)
            )
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.05 * shadowOpacity), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.02 * shadowOpacity), radius: 4, y: 2)
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
