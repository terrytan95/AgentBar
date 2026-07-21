# Access Token Expiry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every Codex account's access-token expiry in the Popover and optionally notify the user 24 hours before expiration.

**Architecture:** Decode only the JWT `exp` claim while `CodexUsageReader` already reads each auth snapshot, then carry the resulting optional `Date` on `UsageAccount`. A pure reminder planner computes deduplicated notification work; a thin `UNUserNotificationCenter` scheduler persists only account-to-expiry registrations and is called by `UsageStore` after refreshes and preference changes.

**Tech Stack:** Swift 6.1, SwiftUI, Foundation, UserNotifications, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Apply only to Codex accounts; Claude Code rows do not show the field.
- Default the reminder setting to off.
- Notify exactly 24 hours before expiry, or immediately when first enabled inside the final 24 hours.
- Do not notify already expired tokens.
- Never retain, log, persist, or display token contents.
- Add no dependencies and no configurable reminder intervals.
- Preserve unrelated worktree changes and keep planning artifacts separate from product commits.

---

### Task 1: Parse and model access-token expiration

**Files:**
- Modify: `Sources/AgentBar/Services/CodexAccountStorage.swift`
- Modify: `Sources/AgentBar/Services/CodexUsageReader.swift`
- Modify: `Sources/AgentBar/Models/UsageModels.swift`
- Test: `Tests/AgentBarTests/UsageParsingTests.swift`

**Interfaces:**
- Produces: `CodexAccountStorage.accessTokenExpiration(from:) -> Date?`
- Produces: `UsageAccount.accessTokenExpiresAt: Date?`
- Consumes: existing active and per-account auth snapshot reads in `CodexUsageReader.read()`

- [ ] **Step 1: Add failing coverage for JWT parsing and account snapshot selection**

Add checks to `testUsageParsingCoverage()` and implement helpers that construct unsigned JWTs:

```swift
try checkCodexAccountStorageParsesAccessTokenExpiration()
try checkCodexReadUsesPerAccountAccessTokenExpirations()

private func checkCodexAccountStorageParsesAccessTokenExpiration() throws {
    let expiry = Date(timeIntervalSince1970: 1_800_086_400)
    let auth = authJSON(
        accessToken: accessToken(expiry: expiry),
        accountID: "acct-a",
        email: "a@example.com"
    ).data(using: .utf8)!

    XCTAssertEqual(CodexAccountStorage.accessTokenExpiration(from: auth), expiry)
    XCTAssertNil(CodexAccountStorage.accessTokenExpiration(from: Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"broken"}}"#.utf8)))
    XCTAssertNil(CodexAccountStorage.accessTokenExpiration(from: Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"secret"}"#.utf8)))
}

private func accessToken(expiry: Date) -> String {
    "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(#"{"exp":\#(Int(expiry.timeIntervalSince1970))}"#))."
}
```

Create a temporary registry with active `acct-a` and inactive `acct-b`, write a newer active auth token for `acct-a`, a stale saved token for `acct-a`, and a saved token for `acct-b`, then assert the reader selects active and saved expiries respectively.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
swift test --filter UsageParsingTests/testUsageParsingCoverage
```

Expected: compilation fails because `accessTokenExpiration(from:)` and `accessTokenExpiresAt` do not exist.

- [ ] **Step 3: Add the minimal parser and model field**

Add to `CodexAccountStorage` using the existing `jwtPayload` helper:

```swift
static func accessTokenExpiration(from authData: Data) -> Date? {
    guard let root = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] else { return nil }
    if firstNonEmptyString([root["OPENAI_API_KEY"]]) != nil { return nil }
    if let authMode = firstNonEmptyString([root["auth_mode"]]),
       authMode.localizedCaseInsensitiveCompare("apikey") == .orderedSame {
        return nil
    }
    let tokens = root["tokens"] as? [String: Any]
    guard let payload = jwtPayload(firstNonEmptyString([tokens?["access_token"], root["access_token"]])),
          let seconds = (payload["exp"] as? NSNumber)?.doubleValue,
          seconds.isFinite,
          seconds > 0
    else { return nil }
    return Date(timeIntervalSince1970: seconds)
}
```

Append the optional field to `UsageAccount` so existing memberwise initializers remain source-compatible:

```swift
var accessTokenExpiresAt: Date? = nil
```

Extend `CodexAuthSnapshotInfo` with `accessTokenExpiresAt`, populate it beside `identity`, and use the active auth info for the active account while inactive accounts use their saved snapshot:

```swift
private struct CodexAuthSnapshotInfo {
    var modifiedAt: Date?
    var identity: CodexAuthIdentity?
    var accessTokenExpiresAt: Date?
}

let savedAuthInfo = authSnapshotInfo?(raw.accountKey)
let selectedAuthInfo = raw.accountKey == activeAccountKey ? (activeAuthInfo ?? savedAuthInfo) : savedAuthInfo
```

Pass `selectedAuthInfo?.accessTokenExpiresAt` into `UsageAccount` and keep credential bytes local to the reader call.

- [ ] **Step 4: Run the focused test and confirm it passes**

Run:

```bash
swift test --filter UsageParsingTests/testUsageParsingCoverage
```

Expected: PASS.

---

### Task 2: Plan and schedule deduplicated expiry reminders

**Files:**
- Create: `Sources/AgentBar/Support/AccessTokenExpiryNotifier.swift`
- Modify: `Sources/AgentBar/Stores/SettingsStore.swift`
- Test: `Tests/AgentBarTests/UsageParsingTests.swift`

**Interfaces:**
- Consumes: `UsageAccount.accessTokenExpiresAt`
- Produces: `AccessTokenExpiryReminderPlanner.plan(accounts:registeredExpirations:enabled:now:language:)`
- Produces: `AccessTokenExpiryDesktopScheduler.reconcile(accounts:enabled:language:)`
- Produces: `SettingsStore.accessTokenExpiryNotificationsEnabled`

- [ ] **Step 1: Add failing planner and preference coverage**

Add checks proving the setting defaults off and persists, and that planning schedules at `expiry - 86_400`, schedules immediately inside the window, skips expired and Claude accounts, skips identical registrations, replaces changed expiries, and clears registrations when disabled.

Use this shape for assertions:

```swift
let plan = AccessTokenExpiryReminderPlanner.plan(
    accounts: [account],
    registeredExpirations: [:],
    enabled: true,
    now: now,
    language: .english
)
XCTAssertEqual(plan.reminders.first?.deliveryDate, expiry.addingTimeInterval(-86_400))
XCTAssertEqual(plan.registrations[account.id], expiry.timeIntervalSince1970)
XCTAssertTrue(AccessTokenExpiryReminderPlanner.plan(
    accounts: [account],
    registeredExpirations: plan.registrations,
    enabled: true,
    now: now,
    language: .english
).reminders.isEmpty)
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run `swift test --filter UsageParsingTests/testUsageParsingCoverage`.

Expected: compilation fails because the planner and setting are missing.

- [ ] **Step 3: Implement the pure plan and macOS scheduler**

Create these value types and planner:

```swift
struct AccessTokenExpiryReminder: Equatable, Sendable {
    var accountID: String
    var expiry: Date
    var deliveryDate: Date
    var title: String
    var body: String

    var notificationID: String { "access-token-expiry-\(accountID)" }
}

struct AccessTokenExpiryReminderPlan: Equatable, Sendable {
    var reminders: [AccessTokenExpiryReminder]
    var notificationIDsToRemove: [String]
    var registrations: [String: TimeInterval]
}

enum AccessTokenExpiryReminderPlanner {
    static let warningInterval: TimeInterval = 86_400

    static func plan(
        accounts: [UsageAccount],
        registeredExpirations: [String: TimeInterval],
        enabled: Bool,
        now: Date,
        language: AppLanguage
    ) -> AccessTokenExpiryReminderPlan
}
```

When enabled, build desired registrations only from unexpired Codex accounts with an expiry. Emit a reminder only when the registered epoch differs, use `max(now, expiry - warningInterval)` as delivery time, and remove the stable account notification ID when an account disappears or changes expiry. When disabled, return no reminders, remove every registered account ID, and return an empty registration map.

Implement `AccessTokenExpiryDesktopScheduler` with `UNUserNotificationCenter` and `UserDefaults`: decode the stored `[String: TimeInterval]`, request alert and sound authorization, remove obsolete pending requests, add immediate requests with a `nil` trigger and future requests with `UNTimeIntervalNotificationTrigger`, then persist registrations only after successfully adding requests. Use one private defaults key and never serialize notification bodies or tokens.

- [ ] **Step 4: Add and persist the setting**

Add the existing `SettingsStore` pattern:

```swift
@Published var accessTokenExpiryNotificationsEnabled: Bool {
    didSet { defaults.set(accessTokenExpiryNotificationsEnabled, forKey: Keys.accessTokenExpiryNotificationsEnabled) }
}
```

Initialize with `defaults.object(forKey:) as? Bool ?? false` and add the matching key constant.

- [ ] **Step 5: Run the focused test and confirm it passes**

Run `swift test --filter UsageParsingTests/testUsageParsingCoverage`.

Expected: PASS.

---

### Task 3: Connect refreshes, settings, Popover, and localization

**Files:**
- Modify: `Sources/AgentBar/Stores/UsageStore.swift`
- Modify: `Sources/AgentBar/Views/PopoverRootView.swift`
- Modify: `Sources/AgentBar/Views/StatisticsView.swift`
- Modify: `Sources/AgentBar/Support/Localization.swift`
- Test: `Tests/AgentBarTests/UsageParsingTests.swift`

**Interfaces:**
- Consumes: Task 1 model expiry and Task 2 scheduler/setting
- Produces: one localized expiry line on Codex Popover rows
- Produces: one notification toggle in the existing Notifications settings group

- [ ] **Step 1: Inject and call reminder reconciliation from `UsageStore`**

Add an injectable closure with a production default:

```swift
private let accessTokenExpiryReminderReconciler: @MainActor @Sendable ([UsageAccount], Bool, AppLanguage) -> Void

accessTokenExpiryReminderReconciler: @escaping @MainActor @Sendable ([UsageAccount], Bool, AppLanguage) -> Void = { accounts, enabled, language in
    AccessTokenExpiryDesktopScheduler.shared.reconcile(accounts: accounts, enabled: enabled, language: language)
}
```

Call it after each refreshed account assignment. Observe `$accessTokenExpiryNotificationsEnabled.dropFirst().removeDuplicates()` so toggling on reconciles current accounts immediately and toggling off cancels pending reminders. Store the cancellable for the lifetime of `UsageStore`.

- [ ] **Step 2: Add the Popover expiry line**

Inside `AccountRowView`, render only for `.codex`:

```swift
if account.service == .codex {
    Label(accessTokenExpiryText, systemImage: "key.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(accessTokenExpiryColor)
        .lineLimit(1)
}
```

For a valid date, combine `DisplayFormatters.shortDateTimeString` and `DisplayFormatters.relativeString`. Return unavailable copy for `nil`, orange for unexpired dates inside 24 hours, red for expired dates, and secondary styling otherwise.

- [ ] **Step 3: Add settings UI and bilingual copy**

Add a `SettingsToggleRow` to the existing Notifications group:

```swift
SettingsToggleRow(
    title: L.text("access_token_expiry_notifications", store.language),
    subtitle: L.text("access_token_expiry_notifications_subtitle", store.language),
    isOn: $settings.accessTokenExpiryNotificationsEnabled
)
```

Add English and Chinese keys for the toggle, expiry label, unavailable state, and notification title/body. The body must include the account display name and localized expiry date, but no credential material.

- [ ] **Step 4: Verify refresh reconciliation through the injected seam**

Add a focused `UsageStore` check that supplies an injected closure, refreshes a snapshot with one expiring Codex account, and asserts the closure receives that account and the current preference. Toggle the setting off and assert a second reconciliation with `enabled == false`.

- [ ] **Step 5: Run focused tests and build**

Run:

```bash
swift test --filter UsageParsingTests/testUsageParsingCoverage
swift build
```

Expected: both commands pass.

---

### Task 4: Final verification, functional commits, and release

**Files:**
- Modify: `script/build_and_run.sh` for the next unused patch version and build number
- Inspect: all changed source, test, documentation, and release files

**Interfaces:**
- Consumes: completed feature and named AgentBar release workflows
- Produces: pushed app commits, verified GitHub release asset, and updated Homebrew cask

- [ ] **Step 1: Run final product validation**

Run:

```bash
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --package
plutil -p dist/AgentBar.app/Contents/Info.plist | rg 'CFBundleShortVersionString|CFBundleVersion'
codesign --verify --deep --strict --verbose=2 dist/AgentBar.app
```

Expected: all tests, verification, packaging, plist assertions, and signature checks pass.

- [ ] **Step 2: Inspect and commit by function**

Inspect `git status --short --branch`, all diffs, and cached stats. Commit the access-token behavior and tests together, documentation separately when present, and the release version/build bump as its own conventional commit. Stage explicit paths only.

- [ ] **Step 3: Push and publish the next verified release**

Push `main`, create the versioned ZIP from the final packaged app, compute SHA-256, publish clear English release notes, and verify the GitHub asset and latest release entry.

- [ ] **Step 4: Update and push Homebrew**

Update `/opt/homebrew/Library/Taps/terrytan95/homebrew-tap/Casks/agentbar.rb` with the released version and SHA-256, run `brew style` and `brew fetch --force`, commit, and push `main`.

- [ ] **Step 5: Confirm final state**

Verify the AgentBar worktree is clean, the app and tap branches match their remotes, and report version/build, app commits, tap commit, release URL, SHA-256, release notes, and validation results.
