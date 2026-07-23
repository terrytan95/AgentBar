# AgentBar animation plans

All plans are stamped against commit `90cdbae`. They are implementation plans,
not completed changes.

| Plan | Title | Severity | Status |
| --- | --- | --- | --- |
| [001](001-unify-press-feedback.md) | Unify immediate press feedback | MEDIUM | TODO |
| [002](002-honor-reduced-transparency.md) | Honor reduced transparency | MEDIUM | TODO |
| [003](003-animate-popover-state-swaps.md) | Animate popover state swaps | MEDIUM | TODO |
| [004](004-animate-live-task-state-changes.md) | Animate live task state changes | MEDIUM | TODO |
| [005](005-animate-audit-disclosures.md) | Animate audit disclosures | LOW | TODO |

## Recommended execution order

1. **001** establishes consistent pressed-state behavior used by later Audit
   work.
2. **002** establishes the accessibility baseline for shared materials.
3. **003** follows 002 because both touch `PopoverRootView.swift`; preserve the
   Reduce Transparency environment while adding Reduce Motion handling.
4. **004** is independent and can run after the shared foundations.
5. **005** follows 001 because both touch `AuditView.swift`; preserve the new
   tactile modifiers.

## Final verification after all plans

1. Run `swift test`.
2. Run `./script/build_and_run.sh --verify`.
3. Launch AgentBar and feel-check every interaction in light/dark appearances,
   then repeat with Reduce Motion and Reduce Transparency independently and
   together.
4. Confirm high-frequency behavior remains instant: menu-bar popover opening,
   chart hover callouts, sorting, pagination, clocks, and per-second task
   duration updates.

Do not commit these planning files unless the user explicitly asks. Execute
plans in order and update each status to `DONE` only after its mechanical and
feel checks pass.
