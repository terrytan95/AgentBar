import AppKit
import ApplicationServices
import Combine
import SwiftUI

private func codexSidebarQuotaAXCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let controller = Unmanaged<CodexSidebarQuotaOverlayController>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        controller.handleAccessibilityChange()
    }
}

@MainActor
final class CodexSidebarQuotaOverlayController: ObservableObject {
    static let shared = CodexSidebarQuotaOverlayController()
    static let codexBundleIdentifier = "com.openai.codex"

    @Published private(set) var hasAccessibilityPermission = AXIsProcessTrusted()

    private weak var settings: SettingsStore?
    private weak var store: UsageStore?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<CodexSidebarQuotaCard>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityObserver: AXObserver?
    private var accessibilityApplication: AXUIElement?
    private var accessibilityWindow: AXUIElement?
    private var codexProcessIdentifier: pid_t?
    private var isStarted = false

    func start(settings: SettingsStore, store: UsageStore) {
        guard !isStarted else { return }
        isStarted = true
        self.settings = settings
        self.store = store
        configurePanel(store: store)
        observeWorkspace()

        settings.$showCodexSidebarQuotaOverlay
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVisibility()
                }
            }
            .store(in: &cancellables)

        store.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.refreshPanelFrame()
                }
            }
            .store(in: &cancellables)

        refreshVisibility()
    }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        cancellables.removeAll()
        clearAccessibilityObservation()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        settings = nil
        store = nil
        isStarted = false
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        refreshVisibility()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated static func panelFrame(
        codexBounds: CGRect,
        contentHeight: CGFloat,
        mainScreenMaxY: CGFloat
    ) -> CGRect? {
        guard codexBounds.width >= 720, codexBounds.height >= 520 else { return nil }
        let sidebarWidth = inferredSidebarWidth(forCodexWindowWidth: codexBounds.width)
        let appKitWindowMinY = mainScreenMaxY - codexBounds.maxY
        return CGRect(
            x: codexBounds.minX + 12,
            y: appKitWindowMinY + 86,
            width: sidebarWidth - 24,
            height: contentHeight
        )
    }

    nonisolated static func inferredSidebarWidth(forCodexWindowWidth width: CGFloat) -> CGFloat {
        // ponytail: Codex exposes only full-window AX geometry; use its responsive sidebar ratio until it exposes a splitter width.
        min(max(width * 0.35, 240), 360)
    }

    func handleAccessibilityChange() {
        refreshFocusedWindowObservation()
        refreshPanelFrame()
    }

    private func configurePanel(store: UsageStore) {
        let card = CodexSidebarQuotaCard(store: store) { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.refreshPanelFrame()
            }
        }
        let hostingView = NSHostingView(rootView: card)
        hostingView.frame = CGRect(x: 0, y: 0, width: 280, height: 1)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = hostingView

        self.hostingView = hostingView
        self.panel = panel
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVisibility()
                }
            }
        }
    }

    private func refreshVisibility() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        guard settings?.showCodexSidebarQuotaOverlay == true,
              hasAccessibilityPermission,
              let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == Self.codexBundleIdentifier
        else {
            panel?.orderOut(nil)
            clearAccessibilityObservation()
            return
        }

        attach(to: application)
        refreshPanelFrame()
    }

    private func attach(to application: NSRunningApplication) {
        guard codexProcessIdentifier != application.processIdentifier || accessibilityObserver == nil else {
            refreshFocusedWindowObservation()
            return
        }
        clearAccessibilityObservation()

        let processIdentifier = application.processIdentifier
        var observer: AXObserver?
        guard AXObserverCreate(processIdentifier, codexSidebarQuotaAXCallback, &observer) == .success,
              let observer
        else {
            panel?.orderOut(nil)
            return
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        [
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification
        ].forEach { notification in
            AXObserverAddNotification(observer, applicationElement, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        codexProcessIdentifier = processIdentifier
        accessibilityObserver = observer
        accessibilityApplication = applicationElement
        refreshFocusedWindowObservation()
    }

    private func refreshFocusedWindowObservation() {
        guard let observer = accessibilityObserver,
              let application = accessibilityApplication,
              let rawWindow = accessibilityAttribute(application, kAXFocusedWindowAttribute as CFString),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID()
        else {
            accessibilityWindow = nil
            panel?.orderOut(nil)
            return
        }
        let window = unsafeDowncast(rawWindow, to: AXUIElement.self)

        if let previous = accessibilityWindow, CFEqual(previous, window) {
            return
        }
        removeWindowNotifications()
        accessibilityWindow = window

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXUIElementDestroyedNotification
        ].forEach { notification in
            AXObserverAddNotification(observer, window, notification as CFString, refcon)
        }
    }

    private func refreshPanelFrame() {
        guard settings?.showCodexSidebarQuotaOverlay == true,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier,
              let window = accessibilityWindow,
              accessibilityAttribute(window, kAXMinimizedAttribute as CFString) as? Bool != true,
              let position = accessibilityPoint(window, kAXPositionAttribute as CFString),
              let size = accessibilitySize(window, kAXSizeAttribute as CFString),
              let hostingView,
              let panel,
              let mainScreenMaxY = NSScreen.screens.first?.frame.maxY
        else {
            panel?.orderOut(nil)
            return
        }

        hostingView.frame.size.width = Self.inferredSidebarWidth(forCodexWindowWidth: size.width) - 24
        hostingView.layoutSubtreeIfNeeded()
        let contentHeight = max(1, ceil(hostingView.fittingSize.height))
        guard let frame = Self.panelFrame(
            codexBounds: CGRect(origin: position, size: size),
            contentHeight: contentHeight,
            mainScreenMaxY: mainScreenMaxY
        ) else {
            panel.orderOut(nil)
            return
        }

        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func clearAccessibilityObservation() {
        removeWindowNotifications()
        if let observer = accessibilityObserver, let application = accessibilityApplication {
            [
                kAXFocusedWindowChangedNotification,
                kAXMainWindowChangedNotification,
                kAXWindowCreatedNotification
            ].forEach { notification in
                AXObserverRemoveNotification(observer, application, notification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        accessibilityWindow = nil
        accessibilityApplication = nil
        accessibilityObserver = nil
        codexProcessIdentifier = nil
    }

    private func removeWindowNotifications() {
        guard let observer = accessibilityObserver, let window = accessibilityWindow else { return }
        [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXUIElementDestroyedNotification
        ].forEach { notification in
            AXObserverRemoveNotification(observer, window, notification as CFString)
        }
    }

    private func accessibilityAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private func accessibilityPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        guard let rawValue = accessibilityAttribute(element, attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func accessibilitySize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let rawValue = accessibilityAttribute(element, attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}
