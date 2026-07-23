# 004 — Animate live task state changes

- **Status**: TODO
- **Commit**: 90cdbae
- **Severity**: MEDIUM
- **Category**: Missed opportunities
- **Estimated scope**: 1 file, about 30 changed lines

## Problem

`LiveTaskCenterView` recomputes task states every second. When task identity or
state actually changes, rows and entire active/recent sections appear, move, or
disappear instantly, so the user loses spatial context.

`Sources/AgentBar/Views/LiveTaskCenterView.swift:7` — current:

```swift
TimelineView(.periodic(from: .now, by: 1)) { timeline in
    let activeTasks = store.tasks.filter { task in
        let state = task.state(at: timeline.date)
        return state == .working || state == .waiting
    }
    let recentTasks = store.tasks.filter { task in
        let state = task.state(at: timeline.date)
        return state == .completed || state == .interrupted
    }
```

`Sources/AgentBar/Views/LiveTaskCenterView.swift:107` — rows currently have no
transition:

```swift
ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
    taskRow(task, now: now)
    if index < tasks.count - 1 { Divider() }
}
```

## Target

Animate only discrete identity/state signatures, never the one-second clock.
Use a 200ms strong ease-out. Normal motion uses opacity plus `.move(edge: .top)`;
Reduced Motion uses opacity only.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

private var taskChangeAnimation: Animation {
    .timingCurve(0.22, 1, 0.36, 1, duration: AgentBarDesign.durationNormal)
}

private var taskChangeTransition: AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
}
```

Inside the timeline closure create stable change keys:

```swift
let activeTaskIDs = activeTasks.map(\.id)
let recentTaskIDs = recentTasks.map(\.id)
let taskStateSignature = store.tasks.map {
    "\($0.id):\($0.state(at: timeline.date).rawValue)"
}
```

Apply the transition to inserted task sections and task rows. Apply local
`.animation(taskChangeAnimation, value:)` modifiers keyed to the two ID arrays
and state signature. Do not key animation to `timeline.date`, durations, token
counts, or costs.

## Repo conventions to follow

- Reuse `AgentBarDesign.durationNormal` and its existing curve values.
- Preserve `ForEach` identity as `task.id`; identity is what makes an
  interruptible transition possible.
- Keep `TimelineView` and the state classification logic unchanged.

## Steps

1. Add the Reduce Motion environment and the two private motion helpers.
2. Compute the three discrete change keys after `activeTasks` and `recentTasks`.
3. Add symmetric transitions to active/recent sections and task rows.
4. Attach animations keyed only to the discrete keys.
5. Confirm task duration text still updates every second without animating.

## Boundaries

- Do NOT animate per-second duration, footer clocks, numeric token/cost updates,
  scrolling, hover, or refresh actions.
- Do NOT use `matchedGeometryEffect`, a spring, bounce, or a timer debounce.
- Do NOT change task state thresholds, sorting, limits, or refresh cadence.
- Do NOT add tests unless explicitly requested; this is a view-only change.

## Verification

- **Mechanical**: run `swift build`; it must exit 0.
- **Feel check**: observe a task go working -> waiting and active -> completed.
  The affected row/section should explain the move without animating unrelated
  rows every second.
- Trigger refresh repeatedly while a transition is active; motion must retarget
  cleanly and never block the refresh button.
- Enable Reduce Motion: state changes must crossfade without vertical movement.
- Use a slow-motion screen recording to confirm enter and exit use the same
  top-edge path and settle within 200ms.
- **Done when**: discrete task lifecycle changes are legible and the normal
  one-second live updates remain visually still.
