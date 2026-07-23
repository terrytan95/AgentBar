# 005 — Animate audit disclosures

- **Status**: TODO
- **Commit**: 90cdbae
- **Severity**: LOW
- **Category**: Missed opportunities
- **Estimated scope**: 1 file, about 25 changed lines

## Problem

Audit task details and nested thread tasks are spatially connected to the row
that triggers them, but they are inserted or removed instantly.

`Sources/AgentBar/Views/AuditView.swift:277` — current task detail:

```swift
ForEach(page(snapshot.sortedTasks, index: clampedPage(tasksPage, total: snapshot.rangeTasks.count))) { task in
    taskRow(task, threadTitle: snapshot.sessionTitle(for: task), nested: false)
    if selectedTaskID == task.id {
        taskDetail(task: task, threadTitle: snapshot.sessionTitle(for: task))
    }
    Divider()
}
```

`Sources/AgentBar/Views/AuditView.swift:290` — current thread disclosure:

```swift
threadRow(thread)
if expandedThreadID == thread.id {
    ForEach(thread.tasks.prefix(20)) { task in
        taskRow(task, threadTitle: thread.title, nested: true)
        if selectedTaskID == task.id {
            taskDetail(task: task, threadTitle: thread.title)
        }
    }
}
```

Current row actions at `AuditView.swift:309` and `AuditView.swift:336` assign
the selection/expansion state without an animation transaction.

## Target

Use a 200ms strong ease-out and a symmetric top-edge transition. Under Reduced
Motion, retain only opacity.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

private var disclosureAnimation: Animation {
    .timingCurve(0.22, 1, 0.36, 1, duration: AgentBarDesign.durationNormal)
}

private var disclosureTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
}
```

Wrap only the state writes in the existing task/thread button actions with
`withAnimation(disclosureAnimation)`. Apply `disclosureTransition` to each
inserted `taskDetail` and to the nested `ForEach` as a group. Preserve current
selection behavior: clicking a task selects it; it does not become a new
collapse toggle.

## Repo conventions to follow

- Reuse `AgentBarDesign.durationNormal` and the established curve.
- Keep the existing stable task/thread IDs and table layout.
- If plan 001 has already run, retain its tactile button modifiers.

## Steps

1. Add the Reduce Motion environment and private disclosure helpers.
2. Wrap `selectedTaskID` changes in the task-row action with
   `withAnimation(disclosureAnimation)`.
3. Wrap `expandedThreadID` and its associated initial task selection in one
   `withAnimation(disclosureAnimation)` transaction.
4. Apply symmetric transitions to task detail and nested thread-task content.
5. Verify sorting and pagination continue to replace content immediately; they
   are high-frequency table operations and are out of scope.

## Boundaries

- Do NOT change selection/collapse semantics, sorting, pagination, export,
  filtering, row height, or table columns.
- Do NOT animate sort changes, page changes, hover, or the whole Audit panel.
- Do NOT use `matchedGeometryEffect`, bounce, blur, stagger, or dependencies.
- If plan 001 changed the same modifier lines, preserve those changes and edit
  only action/transition code.

## Verification

- **Mechanical**: run `swift build`; it must exit 0.
- **Feel check**: expand/collapse threads rapidly and switch between task
  details. Content must originate from the triggering row, reverse cleanly, and
  never leave duplicate details visible.
- Confirm sort headers and pagination remain instant.
- Enable Reduce Motion: nested rows and details must crossfade without moving.
- Review a slow-motion recording to confirm enter and exit share the same path
  and complete within 200ms.
- **Done when**: disclosure changes preserve spatial context without adding
  motion to routine table operations.
