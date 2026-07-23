# 002 — Honor reduced transparency

- **Status**: TODO
- **Commit**: 90cdbae
- **Severity**: MEDIUM
- **Category**: Accessibility
- **Estimated scope**: 2 files, about 35 changed lines

## Problem

The shared panel treatment combines system Material with fixed-alpha custom
colors and a blurred highlight. The popover also uses a translucent gradient
and footer. These custom layers do not branch on macOS Reduce Transparency.

`Sources/AgentBar/Support/AgentBarDesign.swift:101` — current:

```swift
private struct AgentBarPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
```

```swift
shape
    .fill(.regularMaterial)
    .opacity(cornerRadius == 0 ? 0 : 1)
    .overlay {
        shape.fill(cornerRadius == 0 ? AgentBarDesign.appBackground.opacity(0.72) : AgentBarDesign.cardBackground)
    }
```

`Sources/AgentBar/Views/PopoverRootView.swift:118` — current:

```swift
footer
    .padding(.horizontal, PopoverLayout.horizontalInset)
    .frame(height: 62)
    .background(.ultraThinMaterial)
```

`Sources/AgentBar/Views/PopoverRootView.swift:132` — current background is a
three-color `LinearGradient` using `panelHighlight` and a translucent primary
color.

## Target

Use native `accessibilityReduceTransparency`. Normal appearance must remain
pixel-identical. With the setting enabled, shared panels and the popover use
opaque adaptive system colors, no custom blur, and the existing hairline for
separation.

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
```

In each shared panel background branch:

```swift
if reduceTransparency {
    shape.fill(Color(nsColor: .controlBackgroundColor))
} else {
    // Existing light or dark material/alpha/highlight implementation unchanged.
}
```

In `PopoverRootView`:

```swift
@ViewBuilder
private var popoverBackground: some View {
    if reduceTransparency {
        Color(nsColor: .windowBackgroundColor)
    } else {
        LinearGradient(
            colors: [
                AgentBarDesign.panelHighlight,
                AgentBarDesign.appBackground,
                AgentBarPalette.primary.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
```

Use `AnyShapeStyle` only for the footer because its two branches have different
shape-style types:

```swift
.background(
    reduceTransparency
        ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        : AnyShapeStyle(.ultraThinMaterial)
)
```

## Repo conventions to follow

- Keep all shared panel behavior inside `AgentBarPanelModifier`; do not patch
  every `.agentBarPanel(...)` caller.
- Use AppKit adaptive system colors already imported by SwiftUI. Do not invent
  new RGB values or a parallel palette.
- Keep the current dark/light branches, shadows, clipping, and hairlines.

## Steps

1. Add `accessibilityReduceTransparency` to `AgentBarPanelModifier`.
2. Branch only the light and dark background construction: opaque system fill
   under Reduce Transparency, current implementation otherwise.
3. Add the same environment value to `PopoverRootView`.
4. Make `popoverBackground` opaque under Reduce Transparency and branch the
   footer background as shown above.
5. Confirm standalone system Materials elsewhere are untouched; macOS owns
   their accessibility adaptation.

## Boundaries

- Do NOT replace or remove Material in normal mode.
- Do NOT change palette RGB values, corner radii, shadows, or layout.
- Do NOT add an app setting; use the system accessibility environment only.
- Do NOT refactor standalone `.thinMaterial` call sites.
- If SwiftUI cannot infer one conditional shape style, use `AnyShapeStyle` at
  that single site; do not introduce a generic material abstraction.

## Verification

- **Mechanical**: run `swift build`; it must exit 0.
- **Feel check**: compare menu popover and Statistics panels before/after
  toggling Reduce Transparency in System Settings > Accessibility > Display.
  Normal mode must not change. Reduced mode must be opaque and legible with the
  existing border still visible.
- Check light and dark appearances; no background content may bleed through in
  reduced mode.
- Toggle Reduce Motion independently; it must not affect this behavior.
- **Done when**: shared custom translucency becomes opaque only when the system
  preference is enabled, without broad visual restyling.
