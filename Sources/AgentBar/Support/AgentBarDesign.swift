import SwiftUI
import CoreText

enum AgentBarDesign {
    static let radiusMedium: CGFloat = 12
    static var appBackground: Color {
        adaptiveColor(
            light: NSColor.windowBackgroundColor,
            dark: NSColor(calibratedRed: 0.060, green: 0.064, blue: 0.058, alpha: 1)
        )
    }
    static var cardBackground: Color {
        adaptiveColor(
            light: NSColor.controlBackgroundColor.withAlphaComponent(0.78),
            dark: NSColor(calibratedRed: 0.165, green: 0.170, blue: 0.155, alpha: 0.78)
        )
    }
    static var hairline: Color {
        adaptiveColor(
            light: NSColor.separatorColor.withAlphaComponent(0.72),
            dark: NSColor(calibratedWhite: 1, alpha: 0.13)
        )
    }
    static var panelHighlight: Color {
        adaptiveColor(
            light: NSColor.controlBackgroundColor.withAlphaComponent(0.72),
            dark: NSColor(calibratedWhite: 1, alpha: 0.075)
        )
    }
    static var panelGlow: Color {
        adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.28),
            dark: NSColor.white.withAlphaComponent(0.10)
        )
    }
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
    static let chineseFallback = "Source Han Sans SC VF"

    static func registerIfNeeded() {
        _ = registered
    }

    private static let registered: Void = {
        [
            ("IBMPlexSans-Regular", "ttf"),
            ("IBMPlexSans-Medium", "ttf"),
            ("IBMPlexSans-SemiBold", "ttf"),
            ("IBMPlexSans-Bold", "ttf"),
            ("IBMPlexMono-Regular", "ttf"),
            ("IBMPlexMono-Medium", "ttf"),
            ("IBMPlexMono-SemiBold", "ttf"),
            ("IBMPlexMono-Bold", "ttf"),
            ("SpaceGrotesk[wght]", "ttf"),
            ("SourceHanSansSC-VF", "otf")
        ].forEach { name, fileExtension in
            guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Fonts")
            else {
                NSLog("AgentBar font missing: \(name)")
                return
            }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func cascadedFont(family: String, size: CGFloat) -> CTFont {
        registerIfNeeded()

        let fallback = CTFontDescriptorCreateWithNameAndSize(chineseFallback as CFString, size)
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontSizeAttribute: size,
            kCTFontCascadeListAttribute: [fallback]
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

extension Font {
    static func agentBar(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(AgentBarFonts.cascadedFont(family: AgentBarFonts.ui, size: size)).weight(weight)
    }

    static func agentBarMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(AgentBarFonts.cascadedFont(family: AgentBarFonts.mono, size: size)).weight(weight)
    }

    static func agentBarDisplay(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(AgentBarFonts.cascadedFont(family: AgentBarFonts.display, size: size)).weight(weight)
    }
}

private struct AgentBarPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
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
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape
                        .fill(cornerRadius == 0 ? Color(nsColor: .windowBackgroundColor).opacity(0.72) : Color(nsColor: .controlBackgroundColor).opacity(0.78))
                        .overlay(alignment: .top) {
                            shape
                                .stroke(Color(nsColor: .controlBackgroundColor).opacity(cornerRadius == 0 ? 0 : 0.72), lineWidth: 1)
                                .blur(radius: 0.4)
                        }
                }
            }
            .overlay {
                shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.8)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.07 * shadowOpacity), radius: 16, y: 8)
            .shadow(color: .black.opacity(0.035 * shadowOpacity), radius: 3, y: 1)
    }
}

private struct AgentBarGlassSurfaceModifier: ViewModifier {
    var isEnabled: Bool
    var opaqueBackground: AnyShapeStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled && !reduceTransparency {
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                content
                    .background { CodexSidebarMaterialView() }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else {
            content.background(opaqueBackground)
        }
    }
}

private struct AgentBarPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                AgentBarDesign.smoothAnimation(reduceMotion: reduceMotion, duration: AgentBarDesign.durationFast),
                value: configuration.isPressed
            )
    }
}

extension View {
    func agentBarGlassSurface(
        isEnabled: Bool,
        opaqueBackground: AnyShapeStyle
    ) -> some View {
        modifier(
            AgentBarGlassSurfaceModifier(
                isEnabled: isEnabled,
                opaqueBackground: opaqueBackground
            )
        )
    }

    func agentBarPanel(cornerRadius: CGFloat = AgentBarDesign.radiusMedium) -> some View {
        modifier(AgentBarPanelModifier(cornerRadius: cornerRadius))
    }

    func tactilePlainButton(
        enabled isEnabled: Bool = true,
        pressedScale: CGFloat = 0.98
    ) -> some View {
        buttonStyle(AgentBarPressButtonStyle(pressedScale: pressedScale))
            .pointingHandCursor(enabled: isEnabled)
    }
}
