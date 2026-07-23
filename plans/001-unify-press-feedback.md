# 001 — Unify immediate press feedback

- **Status**: TODO
- **Commit**: 90cdbae
- **Severity**: MEDIUM
- **Category**: Physicality & origin
- **Estimated scope**: 5 files, about 35 changed lines

## Problem

AgentBar already has one pointer-down feedback style, but several custom
`.plain` buttons bypass it. Small controls feel inert, while full-width rows do
not acknowledge the press until selection changes on pointer-up.

`Sources/AgentBar/Support/AgentBarDesign.swift:163` — current shared style:

```swift
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
```

The bypasses are:

- `Sources/AgentBar/Views/StatisticsView.swift:229,278,1548,2994,3631`
- `Sources/AgentBar/Views/ProjectBillingView.swift:127`
- `Sources/AgentBar/Views/AuditView.swift:331,371,411,431`

Their current modifier sequence is `.buttonStyle(.plain)` followed by
`.pointingHandCursor(...)` or `.pointingHandCursor()`.

## Target

Keep the existing 150ms strong ease-out and default `0.98` scale for compact
controls. Add an opacity-only variant for wide/high-frequency rows so they
respond immediately without making the whole table pulse. Reduced Motion must
drop scale while retaining the non-spatial opacity response.

```swift
private struct AgentBarPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                AgentBarDesign.smoothAnimation(
                    reduceMotion: reduceMotion,
                    duration: AgentBarDesign.durationFast
                ),
                value: configuration.isPressed
            )
    }
}

extension View {
    func tactilePlainButton(
        enabled isEnabled: Bool = true,
        pressedScale: CGFloat = 0.98
    ) -> some View {
        buttonStyle(AgentBarPressButtonStyle(pressedScale: pressedScale))
            .pointingHandCursor(enabled: isEnabled)
    }
}
```

Use `.tactilePlainButton()` for the compact navigation-layout and info buttons.
Use `.tactilePlainButton(pressedScale: 1)` for the sidebar account selector,
project/session rows, account dropdown, Audit rows, and Audit sort headers. For
the conditionally selectable top-usage row use
`.tactilePlainButton(enabled: isSelectable, pressedScale: 1)`.

## Repo conventions to follow

- Motion values live in `AgentBarDesign`; reuse `durationFast = 0.15` and
  `smoothAnimation(...)` rather than adding another curve or duration.
- `StatisticsView.swift:250` already demonstrates the compact
  `.tactilePlainButton()` call site.
- Preserve `.disabled(...)`, accessibility labels, popovers, help text, and
  button actions exactly.

## Steps

1. Update `AgentBarPressButtonStyle` and `tactilePlainButton` in
   `Sources/AgentBar/Support/AgentBarDesign.swift` to accept `pressedScale`, add
   pressed opacity, and suppress scale under Reduced Motion.
2. In `StatisticsView.swift`, replace the five `.plain`/cursor pairs listed
   above with the target tactile calls. Do not alter the six existing tactile
   call sites.
3. In `ProjectBillingView.swift`, give the project row opacity-only feedback.
4. In `AuditView.swift`, give task rows, thread rows, and both sort-header
   buttons opacity-only feedback.
5. Build and manually verify compact and row-sized controls before proceeding
   to the disclosure-motion plan.

## Boundaries

- Do NOT modify bordered, bordered-prominent, or borderless system buttons.
- Do NOT animate hover, selection, keyboard navigation, or disabled controls.
- Do NOT add a second ButtonStyle or a dependency.
- Do NOT alter action behavior or hit regions.
- If the cited call sites drift from commit `90cdbae`, STOP and report instead
  of applying the modifier mechanically.

## Verification

- **Mechanical**: run `swift build`; it must exit 0.
- **Feel check**: run AgentBar and confirm compact controls scale subtly on
  mouse-down, while table/card rows only dim. Press and release rapidly; the
  response must retarget without jumping or blocking clicks.
- Enable Reduce Motion in macOS Accessibility settings. Compact controls must
  stop scaling but still dim immediately while pressed.
- At slow-motion screen recording playback, confirm no full-row geometry shift
  and no feedback on disabled top-usage rows.
- **Done when**: every listed `.plain` button has immediate feedback and the
  remaining `.plain`/`.borderless` occurrences are deliberate system-style
  exceptions.
