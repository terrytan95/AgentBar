import AppKit
import Carbon
import SwiftUI
import XCTest
@testable import AgentBar

final class QuotaRegressionTests: XCTestCase {
    @MainActor
    func testTimelineTrackStartsAtRangeOrigin() throws {
        let rangeStart = Date(timeIntervalSinceReferenceDate: 0)
        let day: TimeInterval = 86_400
        let account = UsageAccount(
            id: "timeline-test",
            service: .codex,
            displayName: "Timeline test",
            sourceDescription: "test",
            status: .live,
            weeklyWindow: UsageWindow(
                kind: .weekly,
                usedPercent: 100,
                windowMinutes: 7 * 24 * 60,
                resetsAt: rangeStart.addingTimeInterval(9 * day)
            ),
            tokens: .zero,
            isActive: true
        )
        let renderer = ImageRenderer(content: QuotaTimelineTrack(
            account: account,
            window: try XCTUnwrap(account.weeklyWindow),
            rangeStart: rangeStart,
            rangeEnd: rangeStart.addingTimeInterval(14 * day),
            columnCount: 14,
            color: .red,
            language: .english
        ).frame(width: 280, height: 56))
        let image = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let firstRedPixel = (0..<bitmap.pixelsWide).first { x in
            guard let color = bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else {
                return false
            }
            return color.redComponent > color.greenComponent + 0.1
        }

        XCTAssertLessThanOrEqual(try XCTUnwrap(firstRedPixel), 45)
    }

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
