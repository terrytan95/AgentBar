import AppKit
import Carbon
import XCTest
@testable import AgentBar

final class QuotaRegressionTests: XCTestCase {
    func testTimelineTrackUsesFullRemainingRowWidth() {
        XCTAssertEqual(
            QuotaTimelineGeometry.trackWidth(totalWidth: 1_740, accountColumnWidth: 190),
            1_550
        )
    }

    func testPreviewSettingsBackupIsIsolatedFromInstalledApp() {
        let production = SettingsStore.defaultPersistenceURL(bundleIdentifier: "com.terrytan.AgentBar")
        let preview = SettingsStore.defaultPersistenceURL(bundleIdentifier: "com.terrytan.AgentBarPreview")

        XCTAssertEqual(production.lastPathComponent, "Settings.plist")
        XCTAssertEqual(production.deletingLastPathComponent().lastPathComponent, "AgentBar")
        XCTAssertEqual(preview.deletingLastPathComponent().lastPathComponent, "AgentBarPreview")
        XCTAssertNotEqual(production, preview)
    }

    @MainActor
    func testRecorderCapturesShortcutBeforeMenuCommand() throws {
        let button = HotKeyRecorderButton(frame: NSRect(x: 0, y: 0, width: 150, height: 30))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = button
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        var recorded: QuotaWidgetHotKey?
        button.onChange = { recorded = $0 }
        button.performClick(nil)

        let previousMenu = NSApp.mainMenu
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let conflictingItem = NSMenuItem(title: "Conflicting Command", action: nil, keyEquivalent: "w")
        conflictingItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(conflictingItem)
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = previousMenu }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ))
        NSApp.sendEvent(event)

        XCTAssertEqual(recorded?.displayText, "⌘W")
    }
}
