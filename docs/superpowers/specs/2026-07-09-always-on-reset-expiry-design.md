# Always-On Reset Expiry Design

## Goal

Make detailed reset-credit expiry retrieval a permanent AgentBar behavior. Users
must not be able to disable it, and previously saved disabled preferences must
have no effect.

## Current Behavior

The reset page exposes an `Expiry dates` toggle backed by
`SettingsStore.detailedResetCreditsEnabled`. `UsageStore` chooses between a
standard Codex usage synchronizer and a detailed reset-credit synchronizer from
that value. `CodexUsageAPISyncer` also accepts a Boolean that conditionally
requests the reset-credit expiry endpoint.

## Design

Remove the option at every layer instead of representing an always-true Boolean:

1. Remove the expiry-date toggle and its enable-triggered refresh from the reset
   page. The existing manual refresh control remains available.
2. Render reset-expiry results directly. Remove the disabled-state message that
   asks users to enable expiry dates.
3. Remove `detailedResetCreditsEnabled` and its persistence key from
   `SettingsStore`. Existing persisted values become inert because no current
   code reads them.
4. Collapse `UsageStore` to one Codex usage synchronization path. Its production
   synchronizer always retrieves detailed reset-credit expiry data, and refresh
   no longer passes a feature flag.
5. Remove the opt-in parameter from `CodexUsageAPISyncer` and always attempt the
   read-only reset-credit expiry request after a successful usage response.

This makes the invariant explicit: a successful Codex usage refresh always
attempts to enrich the snapshot with detailed reset-credit expiry data.

## Failure Behavior

Detailed expiry retrieval remains best effort. If the reset-credit endpoint is
unavailable or returns unusable data, the successful base usage response still
updates the account snapshot without detailed expiry dates. Existing empty-state
messaging continues to explain that no detailed dates were returned.

## Compatibility

No migration is required. Old `detailedResetCreditsEnabled` values may remain in
`UserDefaults`, but the application no longer reads or writes the key. Removing
the stale value is unnecessary and would add migration-only code without
changing behavior.

## Verification

- Change the API synchronization test so the default initializer proves that
  the detailed reset-credit endpoint is requested and its expiry dates are
  persisted.
- Change the `UsageStore` refresh test so it proves the sole synchronizer is
  used regardless of any legacy preference value.
- Remove assertions that treat detailed expiry retrieval as opt-in.
- Run the targeted usage parsing tests, then the full Swift test suite.

## Out of Scope

- Changing reset-credit parsing, expiry formatting, or reset-spend advice.
- Making detailed expiry failure fatal to base usage refresh.
- Deleting legacy `UserDefaults` data from user machines.
