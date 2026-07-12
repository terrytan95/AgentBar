# Audit Task Performance Metrics Design

## Goal

Replace the Audit page's model-call table with task-level records and add exact
TPS, time-to-first-token, and total-duration metrics for each Codex turn.

## Metric Definitions

- **TPS** is end-to-end output throughput: `output tokens / duration seconds`.
  This matches the supplied reference and includes the wait for the first token.
- **First token** is Codex's reported `time_to_first_token_ms` for the turn.
- **Duration** is Codex's reported `duration_ms` for the completed turn.
- `reasoning_output_tokens` is a subset of output tokens and is not added again
  when calculating TPS.
- Missing, incomplete, non-finite, or non-positive timing data is displayed as
  an em dash. AgentBar must not estimate missing task performance metrics.

## Data Model and Parsing

Extend the task-completion payload decoder with optional `duration_ms` and
`time_to_first_token_ms` values. Carry them through `CodexTaskBuilder` into
optional fields on `AgentTask` so older disk-cache records remain decodable.

Expose derived task helpers for:

- duration in seconds from the reported millisecond value;
- first-token latency in milliseconds;
- TPS when duration is positive and output tokens are available.

The reported duration remains authoritative for the Audit metrics. Existing
`startedAt` and `completedAt` timestamps continue to support task lifecycle and
fallback display elsewhere, but are not substituted for missing performance
fields.

## Audit UI

Rename the Audit page's **Calls** tab to **Tasks** and render one row per Codex
turn instead of one row per internal token-usage point.

The task table columns are:

1. Time
2. Thread
3. Model
4. Reasoning effort
5. TPS
6. First token
7. Duration
8. Total tokens
9. Cached input
10. Uncached input
11. Output
12. Reasoning output

Rows remain selectable and show the existing contextual details that can be
mapped honestly to a task, including identifiers, project/source context,
models, tokens, and cost. The table supports sorting by time, TPS, first-token
latency, duration, and each existing token column. Missing metrics sort after
real values in both directions so unknown data never appears to outperform a
measured task.

The Threads tab remains an aggregate view, but expanded thread contents use the
same task rows. Internal model-call points remain available to usage summaries,
charts, pricing, and aggregation; only the Audit table presentation changes.

## Filtering and Export

Task rows use the selected Audit date range and optional session selection.
Completed tasks are assigned to the range by completion time. Active tasks use
their start time and display missing performance metrics.

The Audit export action exports the records represented by the active tab. Task
exports include task identity/context, timing fields, TPS, token breakdown,
models, and estimated cost. Thread exports preserve their aggregate semantics.
CSV and JSON formatting must represent unavailable metrics as empty/null values,
not zero.

## Compatibility and Error Handling

- All new persisted fields are optional to preserve decoding of existing cache
  records.
- Malformed or unsupported timing values do not prevent the rest of a session
  file from being parsed.
- Duplicate/forked session handling continues to use the existing task identity
  and completeness rules.
- If duplicate task records differ, a record with valid completion timing is
  considered more complete than one without it.
- Claude usage points continue contributing to aggregate usage, but no task row
  is fabricated when the source provides no task lifecycle or timing data.

## Verification

Do not add or modify tests unless separately requested, per repository policy.
Verify the implementation by running the existing targeted usage parsing,
Audit reporting, and layout tests, followed by the complete `swift test` suite
and `./script/build_and_run.sh --verify`. Inspect a current local Codex session
to confirm the displayed values match `duration_ms`,
`time_to_first_token_ms`, and `output_tokens / duration`.

## Out of Scope

- Estimating per-internal-call latency from adjacent JSONL timestamps.
- Pure streaming throughput calculated after subtracting first-token latency.
- Provider-comparison scores, success rates, or color-coded performance grades.
- Changes to existing token pricing or quota calculations.
