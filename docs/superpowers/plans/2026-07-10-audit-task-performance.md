# Audit Task Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Audit model-call rows with exact task-level TPS, first-token latency, and duration records derived from Codex turn lifecycle events.

**Architecture:** Extend `AgentTask` and the Codex JSONL parser with optional reported timing metadata, while preserving the existing point stream for token/cost aggregates. Keep a full untruncated task collection for Audit, project tasks into range-filtered task/thread rows inside `AuditUsageSnapshot`, and serialize those rows through a neutral export record so the view and reporter remain decoupled.

**Tech Stack:** Swift 6, SwiftUI, Foundation JSONL parsing, XCTest verification, Swift Package Manager.

---

## File Structure

- Modify `Sources/AgentBar/Models/UsageModels.swift`: store reported task timing, reasoning effort, and source context; expose validated derived performance values.
- Modify `Sources/AgentBar/Services/CodexUsageReader.swift`: decode task-completion timing and carry it through `CodexTaskBuilder`.
- Modify `Sources/AgentBar/Services/CodexSessionMetricsReader.swift`: prefer duplicate task records with more complete timing metadata.
- Modify `Sources/AgentBar/Stores/UsageStore.swift`: retain the full task collection for Audit separately from the 24-hour Live Tasks collection.
- Modify `Sources/AgentBar/Views/AuditView.swift`: replace call rows with task rows, range/session filtering, task/thread sorting, details, and export selection.
- Modify `Sources/AgentBar/Support/UsageAuditReporter.swift`: add neutral task/thread export records without removing the existing point export API.
- Modify `Sources/AgentBar/Support/Localization.swift`: add English and Chinese task-performance labels and captions.
- Do not modify `Tests/`: repository instructions require explicit authorization for test edits. Use the existing suites and live JSONL verification instead.

### Task 1: Capture Exact Codex Task Performance Metadata

**Files:**
- Modify: `Sources/AgentBar/Models/UsageModels.swift:382-417`
- Modify: `Sources/AgentBar/Services/CodexUsageReader.swift:196-386`
- Modify: `Sources/AgentBar/Services/CodexUsageReader.swift:785-880`
- Modify: `Sources/AgentBar/Services/CodexSessionMetricsReader.swift:292-300`

- [ ] **Step 1: Add optional reported metrics and validated helpers to `AgentTask`**

Add initialized optional properties so all existing memberwise initializers and old disk-cache JSON continue to decode:

```swift
struct AgentTask: Codable, Equatable, Identifiable, Sendable {
    static let waitingAfter: TimeInterval = 5 * 60

    var id: String
    var sessionID: String
    var title: String?
    var projectName: String?
    var cwd: String?
    var repositoryPath: String? = nil
    var sourceFile: String? = nil
    var startedAt: Date
    var completedAt: Date?
    var lastActivityAt: Date
    var tokens: TokenTotals
    var estimatedCostUSD: Decimal?
    var models: [String]
    var reasoningEffort: String? = nil
    var terminalState: AgentTaskState?
    var reportedDurationMilliseconds: Double? = nil
    var timeToFirstTokenMilliseconds: Double? = nil

    var auditDate: Date {
        completedAt ?? startedAt
    }

    var reportedDurationSeconds: TimeInterval? {
        guard let milliseconds = reportedDurationMilliseconds,
              milliseconds.isFinite,
              milliseconds > 0
        else { return nil }
        return milliseconds / 1_000
    }

    var validTimeToFirstTokenMilliseconds: Double? {
        guard let milliseconds = timeToFirstTokenMilliseconds,
              milliseconds.isFinite,
              milliseconds > 0
        else { return nil }
        return milliseconds
    }

    var tokensPerSecond: Double? {
        guard let seconds = reportedDurationSeconds else { return nil }
        return Double(tokens.output) / seconds
    }

    var uncachedInputTokens: Int {
        max(0, tokens.input - tokens.cachedInput)
    }

    // Keep the existing state(at:), duration(at:), and displayProjectName(...)
    // implementations unchanged below these helpers.
}
```

- [ ] **Step 2: Decode task timing fields from `task_complete`**

Extend `CodexSessionPayload` with the exact JSON names:

```swift
private struct CodexSessionPayload: Decodable {
    // Existing properties remain unchanged.
    var durationMilliseconds: Double?
    var timeToFirstTokenMilliseconds: Double?

    enum CodingKeys: String, CodingKey {
        // Existing cases remain unchanged.
        case durationMilliseconds = "duration_ms"
        case timeToFirstTokenMilliseconds = "time_to_first_token_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Existing decoding remains unchanged.
        durationMilliseconds = try? container.decode(Double.self, forKey: .durationMilliseconds)
        timeToFirstTokenMilliseconds = try? container.decode(Double.self, forKey: .timeToFirstTokenMilliseconds)
    }
}
```

Use lenient `try?` decoding specifically for the new metrics so a malformed
optional timing value does not discard an otherwise valid `task_complete`
event. Validation remains centralized in the `AgentTask` helpers.

- [ ] **Step 3: Carry task context through `CodexTaskBuilder`**

Add optional builder fields with defaults, map them into `AgentTask`, and capture the session file path:

```swift
private struct CodexTaskBuilder {
    // Existing properties remain unchanged.
    var sourceFile: String? = nil
    var reasoningEffort: String? = nil
    var reportedDurationMilliseconds: Double? = nil
    var timeToFirstTokenMilliseconds: Double? = nil

    var task: AgentTask {
        AgentTask(
            id: id,
            sessionID: sessionID,
            title: title,
            projectName: projectName,
            cwd: cwd,
            sourceFile: sourceFile,
            startedAt: startedAt,
            completedAt: completedAt,
            lastActivityAt: lastActivityAt,
            tokens: tokens,
            estimatedCostUSD: estimatedCostUSD,
            models: models,
            reasoningEffort: reasoningEffort,
            terminalState: terminalState,
            reportedDurationMilliseconds: reportedDurationMilliseconds,
            timeToFirstTokenMilliseconds: timeToFirstTokenMilliseconds
        )
    }
}
```

In the `task_started` builder construction, pass `sourceFile: sourceFile` and
`reasoningEffort: currentReasoningEffort`. In the active-task update block, add:

```swift
builder.reasoningEffort = currentReasoningEffort ?? builder.reasoningEffort
```

In the `task_complete` / `turn_aborted` block, preserve missing values and capture present values:

```swift
builder.reportedDurationMilliseconds =
    payload.durationMilliseconds ?? builder.reportedDurationMilliseconds
builder.timeToFirstTokenMilliseconds =
    payload.timeToFirstTokenMilliseconds ?? builder.timeToFirstTokenMilliseconds
```

- [ ] **Step 4: Prefer the most complete duplicate task record**

At the start of `AgentTask.isMoreComplete(than:)`, compare timing completeness before the existing activity/token tie-breakers:

```swift
private extension AgentTask {
    func isMoreComplete(than other: AgentTask) -> Bool {
        if terminalState == .completed, other.terminalState != .completed { return true }
        if terminalState == .interrupted, other.terminalState == nil { return true }
        if terminalState == nil, other.terminalState != nil { return false }

        let timingCount = [reportedDurationSeconds, validTimeToFirstTokenMilliseconds]
            .compactMap { $0 }
            .count
        let otherTimingCount = [other.reportedDurationSeconds, other.validTimeToFirstTokenMilliseconds]
            .compactMap { $0 }
            .count
        if timingCount != otherTimingCount { return timingCount > otherTimingCount }

        if lastActivityAt != other.lastActivityAt { return lastActivityAt > other.lastActivityAt }
        return tokens.total > other.tokens.total
    }
}
```

- [ ] **Step 5: Run existing parser coverage**

Run:

```bash
swift test --filter UsageParsingTests
```

Expected: `UsageParsingTests` passes, including the existing task lifecycle fixture that already contains `duration_ms`.

- [ ] **Step 6: Commit the parser/model slice without local planning documents**

```bash
git add Sources/AgentBar/Models/UsageModels.swift \
  Sources/AgentBar/Services/CodexUsageReader.swift \
  Sources/AgentBar/Services/CodexSessionMetricsReader.swift
git commit -m "feat(audit): capture task timings"
```

### Task 2: Keep Full Audit Task History

**Files:**
- Modify: `Sources/AgentBar/Stores/UsageStore.swift:43-49`
- Modify: `Sources/AgentBar/Stores/UsageStore.swift:565-579`
- Modify: `Sources/AgentBar/Stores/UsageStore.swift:605-625`

- [ ] **Step 1: Publish an untruncated Audit task collection**

Add a separate property next to the existing Live Tasks property:

```swift
@Published private(set) var tasks: [AgentTask] = []
@Published private(set) var auditTasks: [AgentTask] = []
```

The existing `tasks` collection keeps its 24-hour / 200-row behavior for
`LiveTaskCenterView`; `auditTasks` must retain all task records returned by the
configured session scan so Audit date ranges remain honest.

- [ ] **Step 2: Update test-data injection consistently**

In `applyTestData(...)`, assign both collections:

```swift
self.tasks = tasks
self.auditTasks = tasks
```

- [ ] **Step 3: Update full history before applying Live Tasks retention**

At the beginning of `applyTaskCenter(_:now:)`, sort the full task set by Audit date and publish only when it changed:

```swift
private func applyTaskCenter(_ nextTasks: [AgentTask], now: Date = Date()) {
    let sortedAuditTasks = nextTasks.sorted { lhs, rhs in
        if lhs.auditDate != rhs.auditDate { return lhs.auditDate > rhs.auditDate }
        return lhs.id > rhs.id
    }
    if auditTasks != sortedAuditTasks {
        auditTasks = sortedAuditTasks
    }

    let previousTasks = tasks
    // Keep the existing history cutoff, sorting, notifications, and refresh
    // bookkeeping below this point unchanged.
}
```

- [ ] **Step 4: Run existing task-store coverage**

Run:

```bash
swift test --filter UsageInsightsTests
swift test --filter UsageParsingTests
```

Expected: both suites pass; existing Live Tasks behavior remains unchanged.

- [ ] **Step 5: Commit the storage boundary**

```bash
git add Sources/AgentBar/Stores/UsageStore.swift
git commit -m "feat(audit): retain task history"
```

### Task 3: Project Tasks and Threads for Audit

**Files:**
- Modify: `Sources/AgentBar/Views/AuditView.swift:638-849`
- Modify: `Sources/AgentBar/Views/AuditView.swift:5-637`
- Modify: `Sources/AgentBar/Support/Localization.swift:250-300`
- Modify: `Sources/AgentBar/Support/Localization.swift:558-608`

- [ ] **Step 1: Replace call-oriented snapshot fields with task-oriented fields**

Use this snapshot shape:

```swift
struct AuditUsageSnapshot {
    var rangePoints: [UsagePoint]
    var rangeTasks: [AgentTask]
    var sortedTasks: [AgentTask]
    var threadRows: [AuditThreadRow]
    var sessionTitles: [String: String]
    var composition: TokenTotals
    var totalCost: Decimal?
    var taskIDs: [String]
}
```

Change `make(...)` to accept `tasks: [AgentTask]`. Build `sessionTitles` from all
Codex points keyed by `sessionID`, filter points with the existing projection,
and filter tasks by `range.dateInterval(...)` using `task.auditDate`. Apply the
selected-session filter with `sessionTitles[task.sessionID] ?? task.title ??
task.sessionID`.

The resulting initializer must have this complete data flow:

```swift
static func make(
    points: [UsagePoint],
    tasks: [AgentTask],
    range: UsageRange,
    customStart: Date?,
    customEnd: Date?,
    selectedSessionLabel: String? = nil,
    sortColumn: AuditSortColumn,
    sortAscending: Bool,
    now: Date = Date(),
    calendar: Calendar = .current
) -> AuditUsageSnapshot {
    let sessionTitles = makeSessionTitles(points)
    let rangePoints = UsageRangeProjection.filteredPoints(
        points: points,
        range: range,
        now: now,
        calendar: calendar,
        customStart: customStart,
        customEnd: customEnd
    )
    .filter { point in
        guard let selectedSessionLabel else { return true }
        return sessionLabel(for: point) == selectedSessionLabel
    }
    .sorted { $0.date > $1.date }

    let interval = range.dateInterval(
        now: now,
        calendar: calendar,
        customStart: customStart,
        customEnd: customEnd
    )
    let rangeTasks = tasks.filter { task in
        guard interval?.contains(task.auditDate) ?? true else { return false }
        guard let selectedSessionLabel else { return true }
        return sessionLabel(for: task, titles: sessionTitles) == selectedSessionLabel
    }
    .sorted { $0.auditDate > $1.auditDate }

    let threadRows = sortedThreads(
        makeThreadRows(rangeTasks, sessionTitles: sessionTitles),
        sortColumn: sortColumn,
        sortAscending: sortAscending
    )

    return AuditUsageSnapshot(
        rangePoints: rangePoints,
        rangeTasks: rangeTasks,
        sortedTasks: sortedTasks(rangeTasks, sessionTitles: sessionTitles, sortColumn: sortColumn, sortAscending: sortAscending),
        threadRows: threadRows,
        sessionTitles: sessionTitles,
        composition: rangePoints.reduce(TokenTotals.zero) { $0 + $1.tokens },
        totalCost: totalCost(rangePoints),
        taskIDs: rangeTasks.map(\.id)
    )
}
```

Use these helpers to keep session identity stable and avoid grouping unrelated
threads that happen to share a title:

```swift
private static func makeSessionTitles(_ points: [UsagePoint]) -> [String: String] {
    points.sorted { $0.date > $1.date }.reduce(into: [:]) { titles, point in
        guard let sessionID = point.sessionID,
              titles[sessionID] == nil
        else { return }
        titles[sessionID] = sessionLabel(for: point)
    }
}

private static func sessionLabel(
    for task: AgentTask,
    titles: [String: String]
) -> String {
    titles[task.sessionID] ?? task.title ?? task.sessionID
}
```

- [ ] **Step 2: Group threads by stable session ID**

Replace the call-based thread row with a task-based row:

```swift
struct AuditThreadRow: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var latest: Date
    var tokens: TokenTotals
    var cost: Decimal?
    var tasks: [AgentTask]
    var reportedDurationMilliseconds: Double?
    var averageTimeToFirstTokenMilliseconds: Double?
    var tokensPerSecond: Double?
}
```

Build rows with `Dictionary(grouping: tasks, by: \.sessionID)`. For each thread:

```swift
let timedTasks = tasks.compactMap { task -> (AgentTask, Double)? in
    guard let duration = task.reportedDurationMilliseconds,
          task.reportedDurationSeconds != nil
    else { return nil }
    return (task, duration)
}
let durationMilliseconds = timedTasks.isEmpty
    ? nil
    : timedTasks.reduce(0) { $0 + $1.1 }
let timedOutputTokens = timedTasks.reduce(0) { $0 + $1.0.tokens.output }
let tps = durationMilliseconds.map { milliseconds in
    Double(timedOutputTokens) / (milliseconds / 1_000)
}
let firstTokenValues = tasks.compactMap(\.validTimeToFirstTokenMilliseconds)
let averageFirstToken = firstTokenValues.isEmpty
    ? nil
    : firstTokenValues.reduce(0, +) / Double(firstTokenValues.count)
```

Use the session-title map for the visible thread title, show task count and
project in the subtitle, sum task token/cost fields, and keep tasks newest first.

- [ ] **Step 3: Add honest optional sorting**

Replace `.initiated` with `.tps` and `.firstToken`:

```swift
enum AuditSortColumn {
    case time
    case thread
    case model
    case effort
    case tps
    case firstToken
    case duration
    case tokens
    case cached
    case uncached
    case output
    case reasoning

    var defaultAscending: Bool {
        switch self {
        case .thread, .model, .effort, .firstToken, .duration:
            true
        case .time, .tps, .tokens, .cached, .uncached, .output, .reasoning:
            false
        }
    }
}
```

Use an optional comparator that always puts missing values last:

```swift
private static func orderedOptional<T: Comparable>(
    _ lhs: T?,
    _ rhs: T?,
    sortAscending: Bool
) -> Bool? {
    switch (lhs, rhs) {
    case let (.some(lhs), .some(rhs)):
        return ordered(lhs, rhs, sortAscending: sortAscending)
    case (.some, .none):
        return true
    case (.none, .some):
        return false
    case (.none, .none):
        return nil
    }
}
```

Task ordering uses `task.auditDate`, the mapped session title,
`task.models.first`, `task.reasoningEffort`, `task.tokensPerSecond`,
`task.validTimeToFirstTokenMilliseconds`, `task.reportedDurationSeconds`, and
the existing token properties. Thread ordering uses the corresponding aggregate
row values.

- [ ] **Step 4: Rename view state and feed full Audit tasks into the snapshot**

Apply these state/name changes consistently:

```swift
@State private var selectedTab: AuditUsageTab = .threads
@State private var selectedTaskID: String?
@State private var expandedThreadID: String?
@State private var exportStatus: String?
@State private var tasksPage = 0
@State private var threadsPage = 0
```

Pass `tasks: store.auditTasks` to `AuditUsageSnapshot.make(...)`, and update the
selection/pagination observer to use `preparedSnapshot.taskIDs` and
`preparedSnapshot.rangeTasks.count`.

- [ ] **Step 5: Rename the Calls tab and Audit copy**

Use `.tasks` instead of `.calls`:

```swift
private enum AuditUsageTab: String, CaseIterable, Identifiable {
    case threads
    case tasks

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.tasks, .chinese): "任务"
        case (.threads, .chinese): "线程"
        case (.tasks, _): "Tasks"
        case (.threads, _): "Threads"
        }
    }
}
```

Add these localization entries in both dictionaries:

```swift
// English
"visible_tasks": "Visible tasks",
"model_tasks": "Tasks",
"tasks": "tasks",
"tasks_caption": "Showing filtered Codex turns with exact reported performance metrics.",
"threads_caption": "Grouped by thread. Click a thread to expand its tasks.",
"tps": "TPS",
"first_token": "First token",
"task_investigator": "Task investigator",
"reported_by_codex": "Reported by Codex",
"end_to_end_throughput": "Output tokens / total duration",

// Chinese
"visible_tasks": "可见任务",
"model_tasks": "任务",
"tasks": "任务",
"tasks_caption": "显示当前筛选范围内的 Codex Turn 与精确上报性能指标。",
"threads_caption": "按线程聚合任务。点击线程展开任务。",
"tps": "TPS",
"first_token": "首 Token",
"task_investigator": "任务详情",
"reported_by_codex": "由 Codex 上报",
"end_to_end_throughput": "输出 Token / 总耗时",
```

Change the status pill and first KPI to `snapshot.rangeTasks.count` with the
task labels; keep token/cost KPI values based on `snapshot.rangePoints`.

- [ ] **Step 6: Render the new performance columns**

Replace the shared table header with this order and widths:

```swift
private var tableHeader: some View {
    HStack(spacing: 8) {
        sortHeader(.time, localized("time"), width: 108, alignment: .leading)
        sortThreadHeader(localized("thread"))
        sortHeader(.model, localized("model"), width: 76)
        sortHeader(.effort, localized("effort"), width: 50)
        sortHeader(.tps, localized("tps"), width: 48)
        sortHeader(.firstToken, localized("first_token"), width: 72)
        sortHeader(.duration, localized("duration"), width: 64)
        sortHeader(.tokens, localized("tokens"), width: 68)
        sortHeader(.cached, localized("cached"), width: 68)
        sortHeader(.uncached, localized("uncached"), width: 68)
        sortHeader(.output, localized("output"), width: 58)
        sortHeader(.reasoning, localized("reasoning"), width: 58)
    }
    .font(.agentBar(size: 11, weight: .bold))
    .foregroundStyle(.secondary)
}
```

Use compact formatters local to `AuditView`:

```swift
private func tpsText(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: "%.0f", value)
}

private func millisecondsText(_ value: Double?) -> String {
    guard let value, value.isFinite, value > 0 else { return "—" }
    if value < 1_000 { return String(format: "%.0f ms", value) }
    if value < 10_000 { return String(format: "%.2f s", value / 1_000) }
    return String(format: "%.1f s", value / 1_000)
}
```

`taskRow(_:nested:)` renders `task.auditDate`, mapped thread title, first model,
reasoning effort, TPS, first token, reported duration, and task token breakdown.
Selection uses `task.id`; row background and detail expansion use
`selectedTaskID`.

`threadRow(_:)` uses aggregate TPS, average first-token latency, summed reported
duration, aggregate tokens, and a `Mixed`/`多模型` presentation when task models
or reasoning efforts differ. Its subtitle remains the visible task count and
project. Expanded rows call `taskRow(_:nested:)` for the first 20 tasks.

- [ ] **Step 7: Replace call details with task details**

Build `taskDetail(task:)` with the task title/session context and a 4-column
detail grid containing:

```swift
detailCard(localized("tps"), tpsText(task.tokensPerSecond), localized("end_to_end_throughput"))
detailCard(localized("first_token"), millisecondsText(task.validTimeToFirstTokenMilliseconds), localized("reported_by_codex"))
detailCard(localized("duration"), millisecondsText(task.reportedDurationMilliseconds), localized("reported_by_codex"))
detailCard(localized("last_call_input"), DisplayFormatters.tokenString(task.tokens.input), localized("exact_from_callback"))
detailCard(localized("cached_input"), DisplayFormatters.tokenString(task.tokens.cachedInput), "")
detailCard(localized("uncached_input"), DisplayFormatters.tokenString(task.uncachedInputTokens), localized("fresh_context"))
detailCard(localized("output"), DisplayFormatters.tokenString(task.tokens.output), localized("assistant_output"))
detailCard(localized("reasoning_output"), DisplayFormatters.tokenString(task.tokens.reasoningOutput), localized("reasoning"))
detailCard(localized("estimated_cost"), costText(task.estimatedCostUSD), localized("configured_price"))
detailCard(localized("model"), task.models.joined(separator: ", ").nilIfEmpty ?? "—", task.reasoningEffort ?? "—")
detailCard("Task ID", task.id, task.sessionID)
detailCard("Cwd", task.cwd ?? "—", task.projectName ?? "—")
```

Do not introduce a new string extension solely for `nilIfEmpty`; implement the
model fallback with a local computed string before building the grid. If
`task.sourceFile` is present, keep the existing Finder reveal button using that
path.

- [ ] **Step 8: Update session selection and pagination**

`applySessionSelection` and `clearSessionSelection` must reset `tasksPage`, use
`snapshot.taskIDs`, expand the first thread, and select the first nested task.
The Tasks paginator uses `snapshot.rangeTasks.count` and the localized task
label. Sorting resets both page indexes.

- [ ] **Step 9: Run existing layout and compile verification**

Run:

```bash
swift test --filter PopoverLayoutTests
swift build
```

Expected: both commands pass with no remaining Calls-tab references in
`AuditView.swift` except intentionally retained backwards-compatible reporter
APIs or localization strings.

- [ ] **Step 10: Commit the projection and UI slice**

```bash
git add Sources/AgentBar/Views/AuditView.swift \
  Sources/AgentBar/Support/Localization.swift
git commit -m "feat(audit): show task performance"
```

### Task 4: Export Task and Thread Performance Rows

**Files:**
- Modify: `Sources/AgentBar/Support/UsageAuditReporter.swift:8-87`
- Modify: `Sources/AgentBar/Views/AuditView.swift:492-616`

- [ ] **Step 1: Add a neutral export record**

Keep the existing `UsagePoint` export functions unchanged for compatibility and
add this record beside `UsageExportFormat`:

```swift
struct UsageAuditPerformanceExportRow {
    var kind: String
    var date: Date
    var sessionID: String
    var sessionTitle: String
    var taskID: String?
    var taskTitle: String?
    var projectName: String?
    var models: String
    var reasoningEffort: String?
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int
    var durationMilliseconds: Double?
    var timeToFirstTokenMilliseconds: Double?
    var tokensPerSecond: Double?
    var estimatedCostUSD: Decimal?
}
```

- [ ] **Step 2: Add CSV and JSON serialization overloads**

Add `serialize(rows: [UsageAuditPerformanceExportRow], format:)`. CSV uses this
exact header:

```text
kind,date,session_id,session_title,task_id,task_title,project,models,reasoning_effort,input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens,total_tokens,duration_ms,time_to_first_token_ms,tps,estimated_cost_usd
```

Serialize missing optional strings/numbers as empty CSV fields. JSON uses the
same snake-case keys and `NSNull()` for absent values. Preserve raw numeric
precision for duration, first-token latency, and TPS; display rounding belongs
only in `AuditView`.

Add this helper for optional numbers:

```swift
private static func doubleString(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "" }
    return String(
        format: "%.3f",
        locale: Locale(identifier: "en_US_POSIX"),
        value
    )
}
```

- [ ] **Step 3: Build export rows from the prepared snapshot**

Add `taskExportRows` and `threadExportRows` computed data to
`AuditUsageSnapshot`. Task rows map exact task fields and the session-title map.
Thread rows set `kind: "thread"`, omit task identity/title, and use the thread's
aggregate tokens, cost, summed duration, average first-token latency, and
weighted TPS.

Use this complete mapping:

```swift
var taskExportRows: [UsageAuditPerformanceExportRow] {
    sortedTasks.map { task in
        UsageAuditPerformanceExportRow(
            kind: "task",
            date: task.auditDate,
            sessionID: task.sessionID,
            sessionTitle: Self.sessionLabel(for: task, titles: sessionTitles),
            taskID: task.id,
            taskTitle: task.title,
            projectName: task.projectName,
            models: task.models.joined(separator: ", "),
            reasoningEffort: task.reasoningEffort,
            inputTokens: task.tokens.input,
            cachedInputTokens: task.tokens.cachedInput,
            outputTokens: task.tokens.output,
            reasoningOutputTokens: task.tokens.reasoningOutput,
            totalTokens: task.tokens.total,
            durationMilliseconds: task.reportedDurationMilliseconds,
            timeToFirstTokenMilliseconds: task.validTimeToFirstTokenMilliseconds,
            tokensPerSecond: task.tokensPerSecond,
            estimatedCostUSD: task.estimatedCostUSD
        )
    }
}

var threadExportRows: [UsageAuditPerformanceExportRow] {
    threadRows.map { thread in
        let models = Array(Set(thread.tasks.flatMap(\.models))).sorted()
        let efforts = Array(Set(thread.tasks.compactMap(\.reasoningEffort))).sorted()
        return UsageAuditPerformanceExportRow(
            kind: "thread",
            date: thread.latest,
            sessionID: thread.id,
            sessionTitle: thread.title,
            taskID: nil,
            taskTitle: nil,
            projectName: thread.tasks.first?.projectName,
            models: models.joined(separator: ", "),
            reasoningEffort: efforts.count == 1 ? efforts[0] : nil,
            inputTokens: thread.tokens.input,
            cachedInputTokens: thread.tokens.cachedInput,
            outputTokens: thread.tokens.output,
            reasoningOutputTokens: thread.tokens.reasoningOutput,
            totalTokens: thread.tokens.total,
            durationMilliseconds: thread.reportedDurationMilliseconds,
            timeToFirstTokenMilliseconds: thread.averageTimeToFirstTokenMilliseconds,
            tokensPerSecond: thread.tokensPerSecond,
            estimatedCostUSD: thread.cost
        )
    }
}
```

- [ ] **Step 4: Export the active tab**

Replace the point-only export body with:

```swift
private func export(format: UsageExportFormat, snapshot: AuditUsageSnapshot) {
    let rows = selectedTab == .tasks
        ? snapshot.taskExportRows
        : snapshot.threadExportRows
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "AgentBar-audit-\(selectedTab.rawValue).\(format.rawValue)"
    panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
        try UsageAuditReporter.serialize(rows: rows, format: format)
            .write(to: url, atomically: true, encoding: .utf8)
        exportStatus = "\(localized("exported")) \(url.lastPathComponent)"
    } catch {
        exportStatus = "\(localized("export_failed")) \(error.localizedDescription)"
    }
}
```

- [ ] **Step 5: Run existing reporter coverage and a focused manual serializer probe**

Run:

```bash
swift test --filter UsageAuditReporterTests
swift build
```

Expected: existing point-export tests remain green and the app compiles with the
new overload. Inspect one generated task CSV and JSON from the running app;
missing timings must be empty/null rather than zero.

- [ ] **Step 6: Commit the export slice**

```bash
git add Sources/AgentBar/Support/UsageAuditReporter.swift \
  Sources/AgentBar/Views/AuditView.swift
git commit -m "feat(audit): export task metrics"
```

### Task 5: Final Verification and Delivery

**Files:**
- Verify only: all implementation files above
- Keep local/uncommitted: `docs/superpowers/specs/2026-07-10-audit-task-performance-design.md`
- Keep local/uncommitted: `docs/superpowers/plans/2026-07-10-audit-task-performance.md`

- [ ] **Step 1: Confirm the implementation diff excludes user and planning files**

Run:

```bash
git status --short
git diff --check
git diff --stat HEAD~4..HEAD
```

Expected: the existing untracked `docs/research/` directory and the two local
planning documents are not staged or committed; implementation diff has no
whitespace errors.

- [ ] **Step 2: Run the complete test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 3: Run the repository verification build**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: verification completes successfully and reports no embedded workspace
paths or packaging/build failures.

- [ ] **Step 4: Verify metric truth against a current local Codex session**

Choose a recent completed session and inspect only metric fields:

```bash
recent=$(rg -l '"type":"task_complete"' "$HOME/.codex/sessions" --glob '*.jsonl' | sort | tail -1)
jq -c 'select(.type == "event_msg" and (.payload.type == "token_count" or .payload.type == "task_complete")) | {timestamp, type: .payload.type, output_tokens: .payload.info.last_token_usage.output_tokens, duration_ms: .payload.duration_ms, time_to_first_token_ms: .payload.time_to_first_token_ms}' "$recent"
```

Expected: for a completed task, the Audit row's first-token latency and duration
match the `task_complete` fields, and TPS equals cumulative task output tokens
divided by `duration_ms / 1000` within display rounding.

- [ ] **Step 5: Inspect the Audit page manually**

Verify in English and Chinese:

- Tasks replaces Calls.
- Task rows, thread expansion, selection, pagination, and sorting work.
- Missing timing values show `—` and sort after measured values.
- TPS uses total duration and does not add reasoning tokens twice.
- Range and session filters change task rows consistently.
- CSV and JSON export the active tab without prompts, replies, or tool output.

- [ ] **Step 6: Push the implementation commits**

Before pushing, invoke the repository's `agentbar-commit-push` workflow to verify
commit scope and remote state. Push the current branch only after all checks
pass; do not stage or commit the local spec, plan, or `docs/research/`.
