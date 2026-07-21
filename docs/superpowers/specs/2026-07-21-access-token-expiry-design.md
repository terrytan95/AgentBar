# Access Token Expiry Design

## Goal

Show each Codex account's access-token expiry in the menu-bar Popover and,
when the user opts in, notify them 24 hours before expiration.

## Scope

- Apply only to Codex accounts. Claude Code rows do not show an access-token
  expiry field.
- Keep the notification preference disabled by default.
- Treat local Codex auth snapshots as read-only credential sources.

## Data Flow

`CodexUsageReader` already reads the active auth file and each saved account
snapshot to identify accounts. Extend that read to decode the `exp` claim from
the JWT access token and place only the resulting `Date` on `UsageAccount`.
Prefer the active auth file for the active account because it contains the
currently refreshed credential; use the saved account snapshot for inactive
accounts.

Missing tokens, malformed JWTs, and missing or invalid `exp` claims produce a
`nil` expiry without failing the account or usage refresh. The raw token must
not enter models, logs, notifications, or persisted AgentBar state.

## Popover

Add one expiry line to every Codex `AccountRowView`:

- Valid future expiry: show the localized date and relative time.
- Less than or equal to 24 hours remaining: use warning styling.
- Expired: show the date and an expired state in red.
- Unavailable expiry: show a localized unavailable value.

The existing account refresh cadence is sufficient to update the relative
display; no additional UI timer is required.

## Settings and Notifications

Add a persisted `accessTokenExpiryNotificationsEnabled` Boolean to
`SettingsStore`, defaulting to `false`, and expose it in the existing
Notifications settings group.

When enabled, reconcile one macOS notification per Codex account:

1. Schedule it for `expiry - 24 hours` when that time is in the future.
2. Deliver it immediately when the token is unexpired but already inside the
   24-hour window.
3. Do not notify for an already expired token.
4. Use the account ID and expiry timestamp as the logical deduplication key so
   periodic refreshes and app restarts cannot repeat the same reminder.
5. Replace an account's pending reminder when a refreshed token has a different
   expiry.
6. Remove pending access-token reminders and their registration records when
   the setting is disabled. Re-enabling intentionally schedules from current
   account state again.

Notification authorization is requested through the existing macOS
`UNUserNotificationCenter` pattern. Denied authorization leaves the preference
enabled but schedules nothing; future reconciliations may retry if system
permission changes.

## Persistence

Persist only the notification preference and the minimal account-to-expiry
registration map needed for deduplication. Do not persist token contents. Clean
records for removed accounts, expired tokens, and replaced expiries during
reconciliation.

## Verification

- Parse valid, missing, malformed, and expired JWT `exp` claims without
  retaining credential strings.
- Verify active accounts prefer the active auth expiry and inactive accounts
  use their saved snapshots.
- Verify notification planning for future, inside-24-hours, expired, replaced,
  disabled, and duplicate cases.
- Verify the new setting defaults to off and persists changes.
- Run focused Swift tests covering parsing and notification decisions, then
  build the app.

## Out of Scope

- Claude Code credential expiry.
- Refreshing or rotating access tokens.
- Configurable warning intervals or multiple reminders.
- Displaying any part of an access token.
