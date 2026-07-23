# 003 — Animate popover state swaps

- **Status**: DONE
- **Commit**: 90cdbae
- **Severity**: MEDIUM
- **Category**: Missed opportunities
- **Estimated scope**: 1 file, about 35 changed lines

## Problem

Two occasional, meaningful popover states teleport: footer actions become a
destructive quit confirmation, and the loading row becomes account content.

`Sources/AgentBar/Views/PopoverRootView.swift:257` — current:

```swift
private var footer: some View {
    Group {
        if isConfirmingQuit {
            quitConfirmation
        } else {
            footerActions
        }
    }
    .padding(.vertical, 8)
}
```

`Sources/AgentBar/Views/PopoverRootView.swift:201` — current:

```swift
if store.isLoadingAccountInformation && store.accounts.isEmpty {
    PopoverLoadingRow(title: L.text("loading_accounts", store.language), subtitle: L.text("loading_account_info_subtitle", store.language))
} else {
    ForEach(store.accountDisplayGroups()) { group in
```

## Target

Use the repo's strong ease-out curve for a 200ms transition. Normal motion uses
opacity plus a subtle `0.97` scale from the state source. Reduced Motion keeps
the 200ms opacity crossfade and drops scale. Both paths are symmetric and
interruptible through SwiftUI transitions.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

private var stateSwapAnimation: Animation {
    .timingCurve(0.22, 1, 0.36, 1, duration: AgentBarDesign.durationNormal)
}

private func stateSwapTransition(anchor: UnitPoint) -> AnyTransition {
    reduceMotion
        ? .opacity
        : .opacity.combined(with: .scale(scale: 0.97, anchor: anchor))
}
```

Apply `.transition(stateSwapTransition(anchor: .trailing))` to both footer
branches and `.animation(stateSwapAnimation, value: isConfirmingQuit)` to the
footer group. Apply the same pattern with anchor `.top` to loading and loaded
account branches, keyed only to:

```swift
store.isLoadingAccountInformation && store.accounts.isEmpty
```

The explicit child `.animation(..., value:)` is required because
`ResizablePopoverRootView` currently clears inherited animation transactions
to keep popover resizing direct.

## Repo conventions to follow

- Reuse `AgentBarDesign.durationNormal = 0.20` and the existing
  `(0.22, 1, 0.36, 1)` curve.
- Keep `ResizablePopoverRootView` height changes unanimated.
- Keep destructive confirmation behavior, keyboard shortcuts, and account
  loading conditions unchanged.

## Steps

1. Add `accessibilityReduceMotion`, `stateSwapAnimation`, and
   `stateSwapTransition(anchor:)` to `PopoverRootView`.
2. Give `footerActions` and `quitConfirmation` symmetric transitions and key
   the local animation to `isConfirmingQuit`.
3. Wrap the loading/loaded account conditional in a `Group`, give both branches
   symmetric transitions, and key its animation only to the loading predicate.
4. Verify rapid quit/cancel reversal starts from the current visual state.
5. Confirm account-data refreshes after initial load do not replay the loading
   entrance unless the loading predicate actually changes.

## Boundaries

- Do NOT animate NSPopover presentation, popover height, scrolling, theme
  changes, account values, or the refresh spinner.
- Do NOT add blur, bounce, delay, stagger, or new dependencies.
- Do NOT remove the root resize transaction.
- Do NOT change quit or loading business logic.

## Verification

- **Mechanical**: run `swift build`; it must exit 0.
- **Feel check**: open the menu popover, press Quit, then Cancel repeatedly.
  Both directions must feel immediate, follow the same path, and never flash
  both layouts at full opacity.
- Start with no loaded account data and confirm the loading row resolves into
  account rows once, without resizing animation.
- Enable Reduce Motion: both swaps must use opacity only, with no scale.
- Review a slow-motion screen recording and confirm scale begins at `0.97`, not
  zero, and the footer remains within its fixed 62pt area.
- **Done when**: both state swaps are clear and reversible while all high-
  frequency popover motion stays disabled.
