# Codex Sidebar Quota Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display the active Codex account's live quota, reset-credit expiry, and access-token expiry in a mouse-transparent glass card attached to the Codex sidebar.

**Architecture:** Extend the existing local auth snapshot metadata with only the access-token `exp` date, then render the current `UsageStore` account in a dedicated SwiftUI card. A main-actor AppKit controller owns one non-activating `NSPanel`, tracks the focused Codex window through Accessibility notifications, and positions the card from the native window frame without modifying Codex.

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, ApplicationServices Accessibility APIs, Combine, XCTest, macOS 14+

## Global Constraints

- Do not modify the Codex Electron bundle, ASAR, DOM, or local application state.
- Do not request Screen Recording permission.
- Never return, log, persist, or display auth JSON, token strings, JWT payloads, email addresses, or account identifiers.
- Default `Show quota in Codex sidebar` to off; request Accessibility permission only after the user explicitly enables it.
- Use a 280-point card, 12-point left inset, 74-point bottom inset, and hide below a 720-by-520-point Codex window.
- Render every available quota window in 5-hour then weekly order; omit absent windows and absent expiry rows.
- Use Codex blue normally, orange below 35 percent remaining, and red below 15 percent.
- Keep the panel non-activating and mouse-transparent.
- Preserve the unrelated untracked `docs/research/2026-07-19-opencodex-multi-chatgpt-accounts.md` file.
- Keep this plan and its design spec local and out of implementation commits.

## File Map

- Modify `Sources/AgentBar/Services/CodexAccountStorage.swift`: decode only the access-token expiry claim.
- Modify `Sources/AgentBar/Services/CodexUsageReader.swift`: carry expiry metadata from the matching auth snapshot into accounts.
- Modify `Sources/AgentBar/Models/UsageModels.swift`: add optional `credentialExpiresAt` account state.
- Create `Sources/AgentBar/Views/CodexSidebarQuotaCard.swift`: presentation state, glass material, compact quota card.
- Create `Sources/AgentBar/App/CodexSidebarQuotaOverlayController.swift`: Accessibility lifecycle, panel ownership, and frame calculation.
- Modify `Sources/AgentBar/App/AgentBarApp.swift`: start and stop the overlay controller with the existing store and settings.
- Modify `Sources/AgentBar/Stores/SettingsStore.swift`: persist the opt-in setting with a false default.
- Modify `Sources/AgentBar/Views/StatisticsView.swift`: add the setting, permission status, and System Settings action.
- Modify `Sources/AgentBar/Support/Localization.swift`: add English and Chinese overlay copy.
- Modify `Tests/AgentBarTests/UsageParsingTests.swift`: cover access-token expiry extraction through the existing auth fixtures.
- Create `Tests/AgentBarTests/CodexSidebarQuotaOverlayTests.swift`: cover window selection state and panel-frame calculation.

---

### Task 1: Carry Access-Token Expiry into `UsageAccount`

**Files:**
- Modify: `Sources/AgentBar/Services/CodexAccountStorage.swift:79-155`
- Modify: `Sources/AgentBar/Services/CodexUsageReader.swift:20-48, 134-185, 601-604`
- Modify: `Sources/AgentBar/Models/UsageModels.swift:140-165`
- Test: `Tests/AgentBarTests/UsageParsingTests.swift:6-90, 2230-2270`

**Interfaces:**
- Produces: `CodexAccountStorage.accessTokenExpiration(from authData: Data) -> Date?`
- Produces: `UsageAccount.credentialExpiresAt: Date?`
- Produces: `CodexAuthSnapshotInfo.credentialExpiresAt: Date?`

- [ ] **Step 1: Add failing auth-expiry checks to the existing coverage test**

Add `try checkCodexAccessTokenExpiryParsing()` to `testUsageParsingCoverage()`, then add this helper and reuse the existing `base64URL` helper:

```swift
private func checkCodexAccessTokenExpiryParsing() throws {
    let expiry = Date(timeIntervalSince1970: 1_800_000_000)
    let accessToken = "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(#"{"exp":1800000000}"#))."
    let authData = try XCTUnwrap(
        #"{"auth_mode":"chatgpt","tokens":{"access_token":"\#(accessToken)","account_id":"acct"}}"#
            .data(using: .utf8)
    )

    XCTAssertEqual(CodexAccountStorage.accessTokenExpiration(from: authData), expiry)
    XCTAssertNil(CodexAccountStorage.accessTokenExpiration(from: Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"secret"}"#.utf8)))
    XCTAssertNil(CodexAccountStorage.accessTokenExpiration(from: Data(#"{"tokens":{"access_token":"malformed"}}"#.utf8)))
}
```

- [ ] **Step 2: Run the focused test and confirm the missing helper failure**

Run: `swift test --filter UsageParsingTests/testUsageParsingCoverage`

Expected: compilation fails because `CodexAccountStorage.accessTokenExpiration(from:)` does not exist.

- [ ] **Step 3: Add the minimum expiry decoder beside the existing identity decoder**

Add this method to `CodexAccountStorage` and keep `jwtPayload` private:

```swift
static func accessTokenExpiration(from authData: Data) -> Date? {
    guard let root = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
          firstNonEmptyString([root["OPENAI_API_KEY"]]) == nil,
          (firstNonEmptyString([root["auth_mode"]])?.localizedCaseInsensitiveCompare("apikey") != .orderedSame),
          let tokens = root["tokens"] as? [String: Any],
          let exp = jwtPayload(firstNonEmptyString([tokens["access_token"]]))?["exp"] as? NSNumber
    else { return nil }
    return Date(timeIntervalSince1970: exp.doubleValue)
}
```

- [ ] **Step 4: Carry the date through the existing auth snapshot closure**

Add a defaulted account property so existing fixtures and decoded snapshots remain compatible:

```swift
var credentialExpiresAt: Date? = nil
```

Extend the private snapshot metadata:

```swift
private struct CodexAuthSnapshotInfo {
    var modifiedAt: Date?
    var identity: CodexAuthIdentity?
    var credentialExpiresAt: Date? = nil
}
```

When reading active and saved auth snapshots, populate both identity and expiry from the same `Data`. In `parseRegistryDetails`, resolve the saved snapshot once, prefer the matching active snapshot for the active account, and pass its date into `UsageAccount`:

```swift
let savedAuthInfo = authSnapshotInfo?(raw.accountKey)
let matchingActiveAuthInfo = raw.matchesAuthIdentity(activeAuthInfo?.identity) ? activeAuthInfo : nil
let currentAuthInfo = matchingActiveAuthInfo ?? savedAuthInfo

// Existing warning expression reuses savedAuthInfo and activeAuthInfo.
credentialExpiresAt: currentAuthInfo?.credentialExpiresAt,
```

- [ ] **Step 5: Run the focused parser coverage**

Run: `swift test --filter UsageParsingTests/testUsageParsingCoverage`

Expected: PASS, including valid, API-key, and malformed access-token cases.

- [ ] **Step 6: Commit only the model, reader, storage, and parser test**

```bash
git add Sources/AgentBar/Models/UsageModels.swift Sources/AgentBar/Services/CodexAccountStorage.swift Sources/AgentBar/Services/CodexUsageReader.swift Tests/AgentBarTests/UsageParsingTests.swift
git commit -m "feat(auth): expose credential expiry"
```

---

### Task 2: Build the Codex-Style Glass Quota Card

**Files:**
- Create: `Sources/AgentBar/Views/CodexSidebarQuotaCard.swift`
- Modify: `Sources/AgentBar/Support/Localization.swift:160-240, 520-590`
- Test: `Tests/AgentBarTests/CodexSidebarQuotaOverlayTests.swift`

**Interfaces:**
- Consumes: `UsageAccount.credentialExpiresAt`, `UsageWindow.resetLine(language:)`, `UsageResetCredits.expirationLines(language:)`
- Produces: `CodexSidebarQuotaCardState.init(account: UsageAccount?)`
- Produces: `CodexSidebarQuotaCard.init(store: UsageStore)`
- Produces: `CodexSidebarMaterialView: NSViewRepresentable`

- [ ] **Step 1: Add failing presentation-state tests**

Create `CodexSidebarQuotaOverlayTests.swift` with a local account helper and these checks:

```swift
import XCTest
@testable import AgentBar

final class CodexSidebarQuotaOverlayTests: XCTestCase {
    func testCardStateShowsEveryAvailableWindowInOrder() {
        let account = account(fiveHour: window(.fiveHour), weekly: window(.weekly))
        XCTAssertEqual(CodexSidebarQuotaCardState(account: account).windows.map(\.kind), [.fiveHour, .weekly])
    }

    func testCardStateOmitsMissingFiveHourWindow() {
        let account = account(fiveHour: nil, weekly: window(.weekly))
        XCTAssertEqual(CodexSidebarQuotaCardState(account: account).windows.map(\.kind), [.weekly])
    }
}
```

The helper constructs `UsageAccount` with `.codex`, zero tokens, the supplied windows, one reset credit expiry, and a credential expiry.

- [ ] **Step 2: Run the new test and confirm the missing-state failure**

Run: `swift test --filter CodexSidebarQuotaOverlayTests`

Expected: compilation fails because `CodexSidebarQuotaCardState` does not exist.

- [ ] **Step 3: Add the narrow presentation state**

Create the state in the new view file:

```swift
struct CodexSidebarQuotaCardState: Equatable {
    var account: UsageAccount?
    var windows: [UsageWindow] {
        guard let account else { return [] }
        return [account.fiveHourWindow, account.weeklyWindow].compactMap { $0 }
    }

    init(account: UsageAccount?) {
        self.account = account
    }
}
```

- [ ] **Step 4: Add the real glass material and compact card**

Implement `CodexSidebarMaterialView` with an `NSVisualEffectView` configured as:

```swift
let view = NSVisualEffectView()
view.material = .sidebar
view.blendingMode = .behindWindow
view.state = .active
```

Implement `CodexSidebarQuotaCard` as a 280-point `TimelineView` that selects:

```swift
store.accounts.first { $0.service == .codex && $0.isActive }
    ?? store.accounts.first { $0.service == .codex }
```

For each state window, render the kind label, remaining percentage, a `ProgressView`, and `window.resetLine(language:)`. Render reset-credit expiration lines and credential expiry only when present. Format credential expiry with `DisplayFormatters.shortDateTimeString` and `DisplayFormatters.relativeString`; use the expired localized copy and red foreground when `expiresAt <= timeline.date`.

Use a local color function:

```swift
private func progressColor(_ remaining: Double) -> Color {
    if remaining < 15 { return .red }
    if remaining < 35 { return .orange }
    return Color(red: 0.36, green: 0.60, blue: 0.98)
}
```

Apply 12-point internal padding, a 12-point continuous rounded clip, a subtle `Color.white.opacity(0.10)` stroke, and a soft black shadow. Keep the view informational and add no buttons or gestures.

- [ ] **Step 5: Add localized copy**

Add matching English and Chinese entries:

```swift
"codex_sidebar_quota": "Codex sidebar quota",
"codex_sidebar_quota_subtitle": "Show the active account quota inside the Codex sidebar.",
"quota_unavailable": "Quota unavailable",
"credential_expires": "Credential expires",
"credential_expired": "Credential expired",
```

```swift
"codex_sidebar_quota": "Codex 侧栏额度",
"codex_sidebar_quota_subtitle": "在 Codex 侧栏显示当前账号额度。",
"quota_unavailable": "额度暂不可用",
"credential_expires": "凭证到期",
"credential_expired": "凭证已过期",
```

- [ ] **Step 6: Run the focused card tests**

Run: `swift test --filter CodexSidebarQuotaOverlayTests`

Expected: both window-order tests PASS.

- [ ] **Step 7: Commit the card, copy, and focused tests**

```bash
git add Sources/AgentBar/Views/CodexSidebarQuotaCard.swift Sources/AgentBar/Support/Localization.swift Tests/AgentBarTests/CodexSidebarQuotaOverlayTests.swift
git commit -m "feat(ui): add Codex quota card"
```

---

### Task 3: Attach the Card to the Focused Codex Window

**Files:**
- Create: `Sources/AgentBar/App/CodexSidebarQuotaOverlayController.swift`
- Modify: `Sources/AgentBar/App/AgentBarApp.swift:37-78`
- Test: `Tests/AgentBarTests/CodexSidebarQuotaOverlayTests.swift`

**Interfaces:**
- Consumes: `CodexSidebarQuotaCard.init(store:)`
- Produces: `CodexSidebarQuotaOverlayController.shared`
- Produces: `start(settings: SettingsStore, store: UsageStore)` and `stop()`
- Produces: `requestAccessibilityPermission()` and `openAccessibilitySettings()`
- Produces: `static panelFrame(codexBounds:contentHeight:mainScreenMaxY:) -> CGRect?`

- [ ] **Step 1: Add failing frame-calculation tests**

Append:

```swift
func testPanelFrameUsesCodexBottomLeftInsets() {
    let frame = CodexSidebarQuotaOverlayController.panelFrame(
        codexBounds: CGRect(x: 100, y: 80, width: 1_200, height: 800),
        contentHeight: 180,
        mainScreenMaxY: 1_440
    )
    XCTAssertEqual(frame, CGRect(x: 112, y: 634, width: 280, height: 180))
}

func testPanelFrameHidesForSmallCodexWindow() {
    XCTAssertNil(CodexSidebarQuotaOverlayController.panelFrame(
        codexBounds: CGRect(x: 0, y: 0, width: 719, height: 800),
        contentHeight: 180,
        mainScreenMaxY: 1_440
    ))
}
```

- [ ] **Step 2: Run the frame tests and confirm the missing-controller failure**

Run: `swift test --filter CodexSidebarQuotaOverlayTests`

Expected: compilation fails because `CodexSidebarQuotaOverlayController` does not exist.

- [ ] **Step 3: Create the panel controller and pure frame function**

Create a `@MainActor final class CodexSidebarQuotaOverlayController: ObservableObject` with `static let shared`, `@Published private(set) var hasAccessibilityPermission`, a weakly repeat-safe `start`, and a `stop` that removes workspace observers, Combine subscriptions, AX notifications, and the panel.

Subscribe to `settings.$showCodexSidebarQuotaOverlay.removeDuplicates()`. Enabling
rechecks trust without prompting and attempts to attach; disabling immediately
orders the panel out and removes the current AX observer.

Use this exact pure function:

```swift
static func panelFrame(
    codexBounds: CGRect,
    contentHeight: CGFloat,
    mainScreenMaxY: CGFloat
) -> CGRect? {
    guard codexBounds.width >= 720, codexBounds.height >= 520 else { return nil }
    let appKitWindowMinY = mainScreenMaxY - codexBounds.maxY
    return CGRect(
        x: codexBounds.minX + 12,
        y: appKitWindowMinY + 74,
        width: 280,
        height: contentHeight
    )
}
```

Configure one panel with:

```swift
let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true
panel.hidesOnDeactivate = false
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
panel.contentView = NSHostingView(rootView: CodexSidebarQuotaCard(store: store))
```

- [ ] **Step 4: Track the Codex app and focused window through Accessibility**

Observe `NSWorkspace.didActivateApplicationNotification`, `didHideApplicationNotification`, and `didTerminateApplicationNotification`. Show only when the frontmost bundle identifier is `com.openai.codex` and Accessibility trust is currently granted.

Create an `AXObserver` for the Codex PID. Register the application element for focused/main-window changes and the focused window for moved, resized, miniaturized, deminiaturized, and destroyed notifications. Each callback returns to `MainActor`, refreshes the focused window reference, extracts `kAXPositionAttribute` and `kAXSizeAttribute`, computes the panel frame, then uses `orderFrontRegardless()` or `orderOut(nil)`.

After setting the SwiftUI root, constrain the hosting view to 280 points, call `layoutSubtreeIfNeeded()`, and use `max(1, hostingView.fittingSize.height)` as `contentHeight`. Subscribe to `store.objectWillChange` and recalculate on the next main-actor turn so quota-driven height changes are reflected.

- [ ] **Step 5: Implement explicit permission actions**

`requestAccessibilityPermission()` calls `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` and updates `hasAccessibilityPermission`. `openAccessibilitySettings()` opens:

```swift
URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
```

The initial `start` path calls `AXIsProcessTrusted()` without prompting.

- [ ] **Step 6: Start and stop the controller from `AppDelegate`**

Resolve one store instance, then pass the same object to both controllers:

```swift
let store = store ?? UsageStore(settings: settings)
StatusItemController.shared.show(settings: settings, store: store)
CodexSidebarQuotaOverlayController.shared.start(
    settings: settings,
    store: store
)
```

Add `applicationWillTerminate` and call `stop()`.

- [ ] **Step 7: Run the focused controller tests and build**

Run: `swift test --filter CodexSidebarQuotaOverlayTests`

Expected: all presentation and frame tests PASS.

Run: `swift build`

Expected: build completes without Swift concurrency or Accessibility callback errors.

- [ ] **Step 8: Commit the controller and app lifecycle wiring**

```bash
git add Sources/AgentBar/App/CodexSidebarQuotaOverlayController.swift Sources/AgentBar/App/AgentBarApp.swift Tests/AgentBarTests/CodexSidebarQuotaOverlayTests.swift
git commit -m "feat(overlay): attach quota to Codex"
```

---

### Task 4: Add the Opt-In Setting and Permission Recovery UI

**Files:**
- Modify: `Sources/AgentBar/Stores/SettingsStore.swift:55-65, 169-205, 273-295`
- Modify: `Sources/AgentBar/Views/StatisticsView.swift:799-840`
- Modify: `Sources/AgentBar/Support/Localization.swift`
- Test: `Tests/AgentBarTests/UsageParsingTests.swift`

**Interfaces:**
- Consumes: `CodexSidebarQuotaOverlayController.shared`
- Produces: `SettingsStore.showCodexSidebarQuotaOverlay: Bool`

- [ ] **Step 1: Add a failing persistence assertion**

Extend the existing settings persistence coverage with an isolated `UserDefaults` suite:

```swift
let defaults = UserDefaults(suiteName: "CodexSidebarQuotaOverlayTests")!
defaults.removePersistentDomain(forName: "CodexSidebarQuotaOverlayTests")
let initial = SettingsStore(defaults: defaults)
XCTAssertFalse(initial.showCodexSidebarQuotaOverlay)
initial.showCodexSidebarQuotaOverlay = true
XCTAssertTrue(SettingsStore(defaults: defaults).showCodexSidebarQuotaOverlay)
defaults.removePersistentDomain(forName: "CodexSidebarQuotaOverlayTests")
```

- [ ] **Step 2: Run parser coverage and confirm the missing-setting failure**

Run: `swift test --filter UsageParsingTests/testUsageParsingCoverage`

Expected: compilation fails because `showCodexSidebarQuotaOverlay` does not exist.

- [ ] **Step 3: Add the false-default persisted setting**

Follow existing settings fields:

```swift
@Published var showCodexSidebarQuotaOverlay: Bool {
    didSet { defaults.set(showCodexSidebarQuotaOverlay, forKey: Keys.showCodexSidebarQuotaOverlay) }
}
```

Initialize with `defaults.object(forKey:) as? Bool ?? false` and add the key string `showCodexSidebarQuotaOverlay`.

- [ ] **Step 4: Add the setting and permission recovery row**

In `StatisticsView`, observe the singleton controller:

```swift
@ObservedObject private var codexOverlay = CodexSidebarQuotaOverlayController.shared
```

Add a second `SettingsGroup` under the menu bar settings group. Bind a `SettingsToggleRow` to the new setting and request permission only on a user-driven false-to-true change:

```swift
SettingsToggleRow(
    title: L.text("codex_sidebar_quota", store.language),
    subtitle: L.text("codex_sidebar_quota_subtitle", store.language),
    isOn: $settings.showCodexSidebarQuotaOverlay
)
.onChange(of: settings.showCodexSidebarQuotaOverlay) { _, enabled in
    if enabled { codexOverlay.requestAccessibilityPermission() }
}
```

When enabled without trust, show a `SettingsRow` with localized permission copy and a button that calls `openAccessibilitySettings()`.

- [ ] **Step 5: Add permission localization**

Add English and Chinese entries for the settings group subtitle, permission-required explanation, and `Open System Settings` button. Keep English and Chinese key sets symmetric.

- [ ] **Step 6: Run focused settings coverage and build**

Run: `swift test --filter UsageParsingTests/testUsageParsingCoverage`

Expected: PASS with false-default and persistence checks.

Run: `swift build`

Expected: PASS.

- [ ] **Step 7: Commit only implementation files**

```bash
git add Sources/AgentBar/Stores/SettingsStore.swift Sources/AgentBar/Views/StatisticsView.swift Sources/AgentBar/Support/Localization.swift Tests/AgentBarTests/UsageParsingTests.swift
git commit -m "feat(settings): enable Codex overlay"
```

---

### Task 5: Verify the Integrated Feature

**Files:**
- Verify only; do not stage the local design, plan, or unrelated research document.

**Interfaces:**
- Consumes: all prior task deliverables.
- Produces: a verified local AgentBar build with the Codex sidebar overlay opt-in available.

- [ ] **Step 1: Run whitespace and scope checks**

Run: `git diff --check`

Expected: no output.

Run: `git status --short`

Expected: only intended source/test changes plus the three known untracked documentation files; no Codex app bundle files.

- [ ] **Step 2: Run the focused tests**

Run: `swift test --filter UsageParsingTests/testUsageParsingCoverage`

Expected: PASS.

Run: `swift test --filter CodexSidebarQuotaOverlayTests`

Expected: PASS.

- [ ] **Step 3: Run the full Swift suite**

Run: `swift test`

Expected: all tests PASS.

- [ ] **Step 4: Verify the packaged app path**

Run: `./script/build_and_run.sh --verify`

Expected: release build succeeds, the generated app verifies, and no local source path is embedded.

- [ ] **Step 5: Perform the manual macOS checks**

Launch the verified AgentBar build, keep the setting off, and confirm no Accessibility prompt appears. Enable the setting and verify the single permission prompt and recovery link. With permission granted, confirm the panel appears only over the frontmost Codex window, follows move/resize/focus, hides on minimize/background/too-small windows, remains mouse-transparent, and does not appear over other apps.

Verify both quota variants, reset-credit expiry, valid/expired/missing credential dates, active-account changes, multiple Codex windows, full screen, and system light/dark appearance. Confirm the normal progress bar is Codex blue and threshold colors remain orange/red.

- [ ] **Step 6: Review the final staged scope before any push**

Run: `git status --short` and `git log -4 --oneline`.

Expected: implementation commits contain only source/test files. The design spec, implementation plan, and unrelated research document remain untracked and uncommitted. Do not push until the normal AgentBar commit/push boundary is confirmed.
