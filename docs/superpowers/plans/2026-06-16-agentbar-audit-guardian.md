# AgentBar Audit Guardian Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Audit and Guardian pages to the Statistics Usage sidebar so AgentBar can explain parsed token usage, generate/export reports, and inspect local agent health safely.

**Architecture:** Keep `UsageStore` as the data source. Add focused support services for audit/report/export and system guardian snapshots, then wire separate SwiftUI page views into `StatisticsView` navigation. High-risk system repair stays recommendation-only in this pass.

**Tech Stack:** Swift 6.1, SwiftUI/AppKit, XCTest, SwiftPM.

---

## File Structure

- Create `Sources/AgentBar/Support/UsageAuditReporter.swift`: audit domain rows, report generation, range filtering, export payloads, CSV/JSON serialization.
- Create `Sources/AgentBar/Support/SystemGuardian.swift`: process/session-store snapshot types, redaction, health classification, recommendation engine, system reader.
- Create `Sources/AgentBar/Views/AuditView.swift`: token breakdown, spike explanation, report copy, CSV/JSON export UI.
- Create `Sources/AgentBar/Views/GuardianView.swift`: process, session, data-source, CPU/storage health UI and safe actions.
- Modify `Sources/AgentBar/Views/StatisticsView.swift`: add Audit/Guardian sidebar entries and route dashboard content by `DashboardViewMode`.
- Test `Tests/AgentBarTests/UsageAuditReporterTests.swift`: audit report and export serialization.
- Test `Tests/AgentBarTests/SystemGuardianTests.swift`: redaction, session classification, recommendation severity.

## Task 1: Usage Audit Domain And Tests

**Files:**
- Create: `Tests/AgentBarTests/UsageAuditReporterTests.swift`
- Create: `Sources/AgentBar/Support/UsageAuditReporter.swift`

- [ ] Write tests for report generation with top model/service, spike explanation, CSV escaping, JSON nil cost handling, and previous-range comparison.
- [ ] Run `swift test --filter UsageAuditReporterTests` and confirm it fails because the reporter does not exist.
- [ ] Implement `UsageAuditReporter`, `AuditBreakdownRow`, `AuditReport`, `UsageRecordExportRow`, `UsageExportFormat`, and serialization helpers.
- [ ] Run `swift test --filter UsageAuditReporterTests` and confirm it passes.

## Task 2: System Guardian Domain And Tests

**Files:**
- Create: `Tests/AgentBarTests/SystemGuardianTests.swift`
- Create: `Sources/AgentBar/Support/SystemGuardian.swift`

- [ ] Write tests for command redaction, missing session path, warning/critical size classification, high CPU process severity, and recommendation generation.
- [ ] Run `swift test --filter SystemGuardianTests` and confirm it fails because the guardian types do not exist.
- [ ] Implement `SystemGuardianSnapshot`, `GuardianProcessRow`, `SessionStoreHealth`, `GuardianRecommendation`, `SystemGuardianReader`, and `GuardianRecommendationEngine`.
- [ ] Run `swift test --filter SystemGuardianTests` and confirm it passes.

## Task 3: Navigation And Audit UI

**Files:**
- Create: `Sources/AgentBar/Views/AuditView.swift`
- Modify: `Sources/AgentBar/Views/StatisticsView.swift`

- [ ] Extend `DashboardViewMode` to `overview`, `audit`, and `guardian`.
- [ ] Add Audit and Guardian sidebar entries below Overview.
- [ ] Route Usage-tab content to Overview for `.overview`, `AuditView` for `.audit`, and `GuardianView` for `.guardian`.
- [ ] Implement Audit UI using `UsageAuditReporter` with token composition cards, service/model rows, spike explanation, report text, copy button, and CSV/JSON export buttons.
- [ ] Run `swift build` to catch SwiftUI integration errors.

## Task 4: Guardian UI And Safe Actions

**Files:**
- Create: `Sources/AgentBar/Views/GuardianView.swift`
- Modify: `Sources/AgentBar/Views/StatisticsView.swift`

- [ ] Implement Guardian UI with summary, process rows, session-store rows, data-source rows, and recommendations.
- [ ] Add direct safe actions: refresh usage, open Codex login, open Claude login, open sessions folder, open Activity Monitor, copy diagnostic report.
- [ ] Keep high-risk actions as text recommendations only.
- [ ] Run `swift build`.

## Task 5: Full Verification

**Files:**
- Modify as needed based on compiler and test feedback.

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `./script/build_and_run.sh --verify`.
- [ ] Confirm `git status --short` only contains intended source/test/plan changes plus pre-existing `.vscode/`.
