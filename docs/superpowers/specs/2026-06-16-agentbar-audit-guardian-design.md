# AgentBar Audit And Guardian Pages

## Decision

AgentBar will add two Usage-tab pages under the Statistics window's left sidebar:

- **Audit:** explains where token usage went, highlights model or daily spikes, generates concise day/week/range reports, and exports parsed usage records.
- **Guardian:** checks local AgentBar/Codex/Claude operating health, including processes, Codex session storage, data-source state, CPU, and storage signals, with low-risk repair actions and confirmation-gated high-risk recommendations.

The implementation uses the existing native SwiftUI Statistics surface, `UsageStore`, `UsageStatistics`, and `UsageInsights` patterns. It does not introduce remote billing APIs, credential reads, destructive cleanup, or constant background sampling in the first pass.

## Product Goals

The current Overview dashboard is good for monitoring current quota and usage. The new pages should answer two adjacent questions:

- **Audit:** why did usage change, and what can be reported or exported?
- **Guardian:** is the local agent environment healthy, and what should be checked or repaired?

The goal is to make AgentBar more useful after the first warning appears. Users should be able to explain usage increases, generate a simple report, export safe records, and inspect local system health without leaving the app for basic diagnostics.

## Navigation

The Statistics left sidebar keeps its current service filter group. The existing `View` group expands from one item to three:

1. **Overview**
   - Keeps the existing quota, KPI, chart, budget, anomaly, and data-source dashboard.
2. **Audit**
   - Shows usage explanation, report generation, and export controls.
3. **Guardian**
   - Shows local process, session store, data-source, CPU, and storage health.

The top `Usage` / `Settings` tab bar remains unchanged. Audit and Guardian live only under `Usage`; settings remain grouped in the Settings tab.

## Audit Page

Audit is a usage explanation workbench. It reuses parsed `UsagePoint` data and derived summaries rather than reading raw session text directly.

### Token Breakdown

The page shows the selected range's token composition:

- Input tokens
- Cached input tokens
- Output tokens
- Reasoning output tokens
- Total tokens
- Estimated cost, when the current pricing table can provide one

It also lists ranked rows by service and model. Ranking is based on total tokens for the active time range.

### Spike Explanation

The page expands the existing anomaly logic into readable explanations:

- Today versus the previous 7-day daily average.
- Current range versus the immediately preceding comparable range.
- Per-model spikes, including model name, current tokens, baseline tokens, and multiple.

All spike copy must state that the analysis is based on local parsed session logs and available rate-limit data, not official billing records.

### Daily, Weekly, And Range Reports

Audit includes a generated report panel. The report follows the selected dashboard range:

- `today` produces a daily report.
- `thisWeek` and `last7Days` produce a weekly-style report.
- Other ranges produce a current-range report.

The report includes:

- Total token count and cost state.
- Top service.
- Top model.
- Largest spike or "no spike detected".
- Budget status for today or this week when applicable.
- Data-source health summary.

The report can be copied to the clipboard.

### Export Records

Audit exports parsed records, not raw session logs.

The first implementation supports:

- CSV export.
- JSON export.

Exported fields:

- Date
- Service
- Model
- Input tokens
- Cached input tokens
- Output tokens
- Reasoning output tokens
- Total tokens
- Estimated cost, when available

The user chooses the save location through a standard macOS save panel. Export failures are shown inline in the page.

### Audit Boundaries

Audit does not:

- Read credential, token, cookie, or private-key files.
- Export raw JSONL session lines.
- Claim authoritative billing accuracy when local subscription sessions do not expose authoritative costs.
- Add remote Admin API integration in this pass.

## Guardian Page

Guardian is a local health and remediation surface. It samples system state on page entry and manual refresh, not continuously.

### Agent Processes

Guardian checks relevant local processes:

- AgentBar
- Codex
- Claude or Claude Code, when present

For each relevant process it shows:

- Process name
- PID
- CPU percentage when available
- Memory when available
- Runtime or start-time signal when available
- Redacted command summary

It flags:

- High CPU usage.
- Multiple likely duplicate processes.
- Long-running helper processes that look stale.

Process command text must be redacted for credential-like words before display.

### Session Store

Guardian checks `~/.codex/sessions`:

- Directory existence.
- Total size.
- JSONL file count.
- Recently modified file count.
- Old or large JSONL count.
- Latest write time.

It classifies session storage as OK, warning, or critical based on size and old-file pressure. The first pass can recommend compaction or cleanup but must not silently delete or move files.

### Data Source Health

Guardian reuses `UsageInsights.dataSourceHealth` and presents a more operational view:

- Service status.
- Last refresh.
- First security note or source note.
- Suggested low-risk action.

Low-risk actions include:

- Refresh usage data.
- Open Codex login.
- Open Claude login.
- Open relevant directories in Finder.

### CPU And Storage Signals

Guardian combines process and session-store signals into a compact system state:

- **OK:** no high CPU and no notable storage pressure.
- **Warning:** elevated CPU, duplicate processes, stale helpers, or growing session storage.
- **Critical:** severe CPU pressure, very large session storage, or unreadable critical paths.

These states are advisory. They should not cause automatic process termination or file mutation.

### Safe Repair Policy

Actions are grouped by risk:

#### Directly Executable

- Refresh usage data.
- Open login flows.
- Open Finder at `~/.codex/sessions`.
- Open Activity Monitor.
- Copy diagnostic report text.

#### Confirmation-Gated Or Recommendation-Only In First Pass

- Terminate stale Codex or Claude helpers.
- Compress or move old session logs.
- Delete caches or generated files.

The first implementation may show these high-risk actions as recommendations with impact text rather than executing them.

#### Never Allowed

- Read or display credentials, tokens, cookies, private keys, or full auth files.
- Delete unknown files.
- Kill the active AgentBar process from inside AgentBar.
- Run broad shell cleanup commands without a narrow target and user confirmation.

## Architecture

### New Domain Types

Add focused types rather than growing `StatisticsView` with system logic:

- `AuditInsight`
- `AuditReport`
- `UsageRecordExportRow`
- `SystemGuardianSnapshot`
- `GuardianProcessRow`
- `SessionStoreHealth`
- `GuardianRecommendation`

These should be plain Swift value types where practical.

### New Services

Add small services with testable pure helpers:

- `UsageAuditReporter`
  - Builds breakdowns, comparisons, report text, and export rows from `[UsagePoint]`, summaries, budgets, and data-source health.
- `UsageExportWriter`
  - Serializes export rows as CSV or JSON and writes to a user-selected URL.
- `SystemGuardianReader`
  - Samples process and filesystem health.
- `GuardianRecommendationEngine`
  - Converts health signals into severity and action recommendations.

### UI Composition

`StatisticsView` should keep navigation state and route to page-level views:

- `OverviewDashboardView` or the existing overview stack.
- `AuditView`
- `GuardianView`

If extracting the full existing overview is too large for one pass, the first implementation can keep the current overview methods in `StatisticsView` and add separate `AuditView` / `GuardianView` components.

## Error Handling

Audit errors:

- Export write failures show the failed destination and error description when safe.
- Empty usage data shows an honest empty state.
- Missing cost data shows `N/A`, not `$0`.

Guardian errors:

- Missing paths show "not found" with a suggested action when available.
- Permission failures show the path category and error, not hidden internals.
- Process sampling failures show a degraded health state rather than crashing the page.

## Testing Plan

Add focused tests for:

- Audit report generation for normal, empty, spike, and budget-warning cases.
- CSV and JSON export serialization, including escaping and nil cost values.
- Current-range versus previous-range comparison math.
- Guardian command redaction.
- Session store classification by size, file count, old-file count, and missing path.
- Guardian recommendation severity.

Run before completion:

- `swift test`
- `swift build`
- `./script/build_and_run.sh --verify`

For UI smoke verification:

- Open Statistics.
- Confirm sidebar includes Overview, Audit, and Guardian.
- Confirm Audit renders with current data and export/copy controls.
- Confirm Guardian renders process/session/data-source health without visible secrets.

## Out Of Scope

- Remote OpenAI or Anthropic Admin API billing integration.
- Long-running background process monitoring.
- Automatic destructive session cleanup.
- Silent process termination.
- Notarization, packaging changes, or release publication unless requested after implementation.

## Open Decisions Resolved

- Guardian uses the safe execution policy: low-risk actions can run directly, high-risk actions require confirmation or stay recommendation-only in the first pass.
- Audit and Guardian are separate pages under the Statistics Usage sidebar, not modal sheets and not merged into Overview.
