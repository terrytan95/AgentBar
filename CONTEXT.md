# AgentBar

AgentBar tracks local AI usage, quota windows, account state, and update status for the menu bar app.

## Language

**Usage range**:
A selected time span used to slice usage records for summaries, reports, comparisons, and exports.
_Avoid_: Date filter, reporting period

**Usage refresh**:
The orchestration pass that syncs remote quota data, reads local usage snapshots, and merges them into app state.
_Avoid_: Reload, fetch all data

**Codex account lifecycle**:
The flow that switches, removes, recovers, and refreshes Codex accounts while preserving the active account state.
_Avoid_: Account action, account button flow

**Codex usage source**:
The local and remote Codex data used to build usage accounts, quota windows, reset credits, and usage points.
_Avoid_: Codex parser, session files
