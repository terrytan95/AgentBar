# Codex Sidebar Quota Overlay Design

## Goal

Show the active Codex account's quota and expiry information in a compact
AgentBar-owned widget attached to the bottom of the Codex sidebar. The widget
must look native to the Codex window without modifying Codex, its signed ASAR,
or its update path.

## Current Behavior

AgentBar already reads Codex quota windows and reset-credit expiry data. Its
popover account rows render the remaining percentage and reset time for the
available 5-hour and weekly windows. AgentBar does not currently place any UI
over the Codex app, and it does not expose the access-token expiry carried in
the local Codex authentication snapshot.

The installed Codex app is an Electron application with ASAR integrity
verification. Direct injection would break signing and updates, so the feature
will be an external AppKit overlay owned entirely by AgentBar.

## User-Visible Behavior

- Add an opt-in `Show quota in Codex sidebar` setting. It defaults to off so an
  AgentBar update never triggers an unexpected Accessibility permission prompt.
- When enabled and Codex is frontmost, attach one compact card to the bottom-left
  of the focused Codex window, immediately above the account strip.
- Show the active Codex account only.
- Render every available quota window. When both 5-hour and weekly windows are
  available, show both; when the 5-hour window is absent, show weekly only.
- For each window, show its name, remaining percentage, progress bar, and reset
  time as both an absolute timestamp and relative duration.
- Show reset-credit expiry lines only when Codex returned `expires_at` values.
- Show the access-token JWT expiry as `Credential expires`. Do not display the
  ID-token expiry because that short-lived claim does not represent the usable
  login credential. Refresh the displayed date whenever AgentBar refreshes the
  account snapshot.
- Hide individual rows whose source field is absent. If an active account exists
  but quota windows are unavailable, show `Quota unavailable` while retaining
  any available expiry information.

## Architecture

### Credential Expiry

Reuse `CodexAccountStorage`'s existing JWT payload decoder. Add a narrow helper
that reads only the access token's numeric `exp` claim and converts it to a
`Date`. It must never return, log, persist, or expose the token string or the
decoded payload.

Add an optional credential-expiry date to `UsageAccount`. Populate it in
`CodexUsageReader` from the matching saved account authentication snapshot, the
same local file already used to resolve account identity. A missing, malformed,
or API-key-backed authentication file yields `nil` without failing the usage
snapshot.

### Overlay Controller

Add one main-actor overlay controller owned by `AppDelegate`. It manages a
single borderless, non-activating, transparent `NSPanel` containing a SwiftUI
quota view backed by the existing `UsageStore`.

The controller will:

1. Observe workspace activation and Codex lifecycle notifications.
2. When the setting is enabled, request Accessibility trust once from the
   explicit user action.
3. Resolve the focused window for bundle identifier `com.openai.codex` and
   observe window move, resize, minimize, and focus changes.
4. Recalculate the panel frame from the focused Codex window frame, using a
   12-point left inset and a 74-point bottom inset.
5. Order the panel out when Codex is not frontmost, has no usable main window,
   is minimized, or the window is smaller than 720 by 520 points.

The panel ignores mouse events, does not activate AgentBar, joins full-screen
spaces, and is visible only while its matching Codex window is frontmost. It
does not use screen capture, DOM injection, private Electron APIs, or polling of
Codex application data.

Electron currently exposes the native window geometry but not a reliable
sidebar sub-element frame through Accessibility. The first version therefore
uses a stable bottom-left window inset and the standard Codex sidebar card
width. The settings toggle is the escape hatch when a future Codex layout no
longer provides suitable space.

## Layout and Visual Style

- Use a 280-point-wide card with dynamic height, a 12-point
  continuous corner radius, a subtle border, and a soft shadow.
- Back the card with an active `NSVisualEffectView` sidebar material so the blur
  is real and follows system light/dark appearance.
- Match the compact type scale and spacing of the Codex sidebar. Use monospaced
  digits for percentages and timestamps.
- Use Codex blue for normal progress. Preserve AgentBar's warning semantics by
  changing the bar to orange below 35 percent remaining and red below 15
  percent.
- Keep the entire panel mouse-transparent. The card is informational only; all
  refresh, account, and permission actions remain in AgentBar.

## Error and Permission Behavior

- Permission denied: keep the panel hidden, show permission status in AgentBar
  settings, and provide an action to open the relevant System Settings pane.
  Do not repeatedly prompt.
- Missing or unreadable auth snapshot: omit credential expiry and preserve the
  rest of the account display.
- Expired access token: show `Credential expired` in red. This is the token's
  claim state, not a promise that refresh-token renewal has also failed.
- Missing reset timestamp or reset-credit expiry: omit only the unavailable
  value instead of inventing one.
- Codex closed, hidden, minimized, backgrounded, or too small: order the overlay
  out immediately.
- Multiple Codex windows: attach only to the focused main window.

## Security and Privacy

- Parse only the local access token's `exp` claim.
- Never include auth JSON, token strings, JWT payloads, email addresses, or
  account identifiers in overlay logs or diagnostics.
- Do not modify Codex files or request Screen Recording permission.
- Reuse AgentBar's existing local-file permission failure handling.

## Verification

- Add focused checks for access-token `exp` parsing, malformed or missing JWTs,
  and API-key-backed auth files.
- Add a focused check that the overlay presentation model includes all available
  quota windows, omits a missing 5-hour window, and formats expired credentials.
- Add a focused check for window-frame calculation and the too-small-window
  hiding boundary.
- Run the affected Swift tests and `swift build`.
- Manually verify enable/disable, permission granted/denied, app switching,
  window movement/resizing/minimization, multiple windows, full screen,
  light/dark appearance, weekly-only data, reset-credit expiry, expired/missing
  credentials, and active-account changes.

## Out of Scope

- Patching or injecting into the Codex Electron bundle.
- Reading Codex DOM state or using screen capture to detect sidebar visibility.
- Interactive controls inside the overlay.
- Showing inactive Codex accounts in the overlay.
- Adding a second quota data source or network request.
