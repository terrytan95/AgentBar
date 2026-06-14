# AgentBar cc-bar Inspired Redesign

## Decision

AgentBar will use two distinct surfaces:

- **Menu bar dropdown:** adopt the dense, quota-first structure of the cc-bar overview popover. This is the A direction from the visual comparison.
- **Dedicated app window:** adopt the analytics workbench structure from the C direction: sidebar filters, range controls, KPI cards, charts, limits, service mix, model details, and grouped settings.

The implementation should reference cc-bar's information architecture and interaction model, not copy its protected assets, exact screenshots, logos, or proprietary styling. AgentBar keeps its own generated icon, SwiftPM app structure, real read-only data sources, and bilingual copy.

## Product Goals

The current AgentBar UI exposes the right data but feels too loose and card-heavy. The redesign should make the app feel like a serious menu bar utility:

- Show quota state immediately after clicking the menu bar icon.
- Support all logged-in Codex accounts without hiding secondary accounts.
- Separate quick monitoring from deeper analytics.
- Keep controls close to the workflow: refresh, statistics, settings, HUD, quit.
- Preserve real-data-only behavior. Empty or unavailable states must be honest, not mocked.

## Menu Bar Dropdown

The popover becomes a compact quota console with fixed visual hierarchy:

1. **Header**
   - Title: localized "Usage".
   - Subtitle: relative last refresh time or clear unavailable/error state.
   - Status dot: live, stale, unavailable, or partial.
   - Icon buttons: refresh, statistics, settings, HUD toggle, quit.

2. **Primary service blocks**
   - Codex and Claude Code each get a service block when enabled.
   - Each block has a service tile, service name, plan or source status, and live dot.
   - The dominant value is remaining percentage for the 5-hour window.
   - The main row includes reset time and a horizontal quota bar.
   - Weekly quota appears as a second compact row.
   - Today/week cost remains visible but displays `N/A` when no authoritative source exists.

3. **Other Codex accounts**
   - All secondary Codex accounts are shown in one dense section.
   - No `prefix(4)` or fixed account cap.
   - Each row shows account name or username, plan when available, 5H and WK progress rows, percent, and reset time.
   - The section scrolls only when needed, keeping the popover usable with 8+ accounts.
   - The menu bar dropdown height grows with account count until a safe maximum height, rather than staying at a fixed short height.

4. **Data source state**
   - Long security/source notes are removed from the main popover body.
   - The popover shows concise state labels only.
   - Detailed notes move to settings or the dedicated app window.

The popover should target roughly `340-380pt` width and favor dense typography, monospaced digits, hairline dividers, and compact progress bars over large repeated cards.

## Dedicated App Window

Opening the app should show a real utility window, not just a launch status card. It should use the C direction:

1. **Sidebar**
   - Service filters: All, Codex/OpenAI, Claude/Anthropic.
   - View modes: Overview, Timeline, Details when implemented.
   - Native macOS sidebar feel, not nested cards.

2. **Top controls**
   - Segmented time range picker: today, yesterday, week, month, year, 7 days, 30 days, all, custom.
   - Refresh button and last refreshed state.
   - Custom range controls appear only for custom.

3. **Overview**
   - KPI row for total tokens, estimated cost, Codex/OpenAI, Claude/Anthropic.
   - Daily stacked bar chart.
   - Service mix panel.
   - Current limits panel with compact rings or progress rows.
   - Model detail panel with input/output/cost columns where available.

4. **Settings**
   - Replace the current tabbed `Form` with grouped preference sections:
     - Accounts
     - Menu Bar
     - Floating HUD
     - Refresh
     - General
   - Use rows with labels, short descriptions, and controls aligned to the trailing edge.

5. **Launch behavior**
   - Finder/app launch opens the dedicated app window.
   - Menu bar click opens the quota popover.
   - HUD stays optional and non-activating.

## Design System

AgentBar should use a restrained native macOS utility palette:

- Semantic backgrounds and materials for light/dark support.
- Service identity colors:
  - Codex/OpenAI: neutral graphite.
  - Claude/Anthropic: warm coral.
- Status color is based on remaining quota, not arbitrary service color:
  - Healthy: neutral/green depending on context.
  - Warning: amber.
  - Low: orange/red.
  - Unknown: secondary gray.
- Progress bars and rings use monospaced percent labels.
- Cards use small radii and hairline strokes. Avoid large decorative app-logo cards inside the utility surfaces.

## Data Flow

No new data-source assumptions are introduced in this redesign.

- `UsageStore` remains the app-wide source for accounts, quota windows, usage points, refresh state, and settings.
- `CodexUsageReader` continues read-only parsing of local registry/session sources.
- `ClaudeUsageReader` continues honest unavailable/authorization-needed reporting unless a real safe source exists.
- The popover and main app window should consume the same store-derived view models so account counts and quota values cannot drift between surfaces.

## Error And Empty States

- If no services are enabled, the popover shows a compact "No services enabled" state with a settings action.
- If accounts are present but quota windows are missing, rows show `--%` and source state rather than disappearing.
- If Claude Code has no safe local account or usage source, it does not create a placeholder account row in the UI.
- Credential, token, cookie, session, or private key values must never be printed, committed, or shown.

## Implementation Scope

The first implementation pass should include:

- New reusable design components: service tile, compact progress bar, status color helper, panel modifier, compact icon button.
- Reworked `PopoverRootView` using the A layout.
- Reworked `LaunchStatusView` or replacement main app root using the C layout for app launch.
- Reworked `StatisticsView` toward the C dashboard structure.
- Reworked `SettingsView` into grouped preference sections.
- Regression tests for account list display and formatting helpers where practical.
- Build, smoke report, installed app launch verification, and screenshot evidence.

Out of scope for this pass:

- Copying cc-bar assets, screenshots, or exact source files.
- Adding unsafe credential import flows.
- Notarization or Apple Developer distribution.
- Mutating the existing v0.0.3 release.

## Verification Plan

Run these checks before completion:

- `swift test`
- `./script/build_and_run.sh --package`
- `./script/build_and_run.sh --verify`
- `codesign --verify --deep --strict dist/AgentBar.app`
- Smoke report account count check without printing sensitive account details.
- Screenshot pass for:
  - menu bar dropdown showing all 8 Codex accounts,
  - dedicated app window dashboard,
  - grouped settings,
  - HUD unchanged or still functional.

## Open Questions Resolved

- Menu bar dropdown uses A.
- Dedicated app window uses C.
- The redesign references cc-bar's structure but does not copy protected assets.
