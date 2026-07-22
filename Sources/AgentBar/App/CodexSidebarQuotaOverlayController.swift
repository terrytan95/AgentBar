import AppKit
import ApplicationServices
import Combine
import SwiftUI

struct CodexDisplayGeometry {
    var accessibilityFrame: CGRect
    var appKitFrame: CGRect
}

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
    private var panelMoveObserver: NSObjectProtocol?
    private var frameRefreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityObserver: AXObserver?
    private var accessibilityApplication: AXUIElement?
    private var accessibilityWindow: AXUIElement?
    private var codexProcessIdentifier: pid_t?
    private var lastCodexBounds: CGRect?
    private var framePollCount = 0
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

        settings.$codexSidebarQuotaOverlayIndependent
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

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.settings?.codexSidebarQuotaOverlayIndependent == false else { return }
                self?.pollAttachedPanelFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameRefreshTimer = timer

        refreshVisibility()
    }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        if let panelMoveObserver {
            NotificationCenter.default.removeObserver(panelMoveObserver)
        }
        panelMoveObserver = nil
        frameRefreshTimer?.invalidate()
        frameRefreshTimer = nil
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
        guard settings?.codexSidebarQuotaOverlayIndependent != true else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        refreshVisibility()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated static func shouldShowOverlay(
        enabled: Bool,
        independent: Bool,
        hasAccessibilityPermission: Bool,
        isCodexFrontmost: Bool
    ) -> Bool {
        enabled && (independent || (hasAccessibilityPermission && isCodexFrontmost))
    }

    nonisolated static func panelFrame(
        codexBounds: CGRect,
        sidebarWidth: CGFloat? = nil,
        accountMenuBounds: CGRect? = nil,
        contentHeight: CGFloat,
        mainScreenMaxY: CGFloat
    ) -> CGRect? {
        guard codexBounds.width >= 720, codexBounds.height >= 520 else { return nil }
        let sidebarWidth = sidebarWidth ?? inferredSidebarWidth(forCodexWindowWidth: codexBounds.width)
        if let accountMenuBounds {
            return CGRect(
                x: codexBounds.minX + 12,
                y: mainScreenMaxY - accountMenuBounds.minY + 12,
                width: sidebarWidth - 24,
                height: contentHeight
            )
        }
        let appKitWindowMinY = mainScreenMaxY - codexBounds.maxY
        return CGRect(
            x: codexBounds.minX + 12,
            y: appKitWindowMinY + 86,
            width: sidebarWidth - 24,
            height: contentHeight
        )
    }

    nonisolated static func appKitCoordinateMaxY(
        for codexBounds: CGRect,
        displays: [CodexDisplayGeometry]
    ) -> CGFloat? {
        var best: (display: CodexDisplayGeometry, area: CGFloat)?
        for display in displays {
            let intersection = display.accessibilityFrame.intersection(codexBounds)
            let area: CGFloat = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > (best?.area ?? 0) {
                best = (display, area)
            }
        }
        return best.map { $0.display.appKitFrame.maxY + $0.display.accessibilityFrame.minY }
    }

    nonisolated static func accountMenuBounds(
        candidates: [CGRect],
        codexBounds: CGRect,
        sidebarWidth: CGFloat? = nil
    ) -> CGRect? {
        let sidebarWidth = sidebarWidth ?? inferredSidebarWidth(forCodexWindowWidth: codexBounds.width)
        let minimumMenuBottom = codexBounds.maxY - 160
        let maximumMenuHeight = codexBounds.height * 0.65

        let menu = candidates
            .filter { candidate in
                candidate.width >= 160
                    && candidate.width <= sidebarWidth + 24
                    && candidate.height >= 80
                    && candidate.height <= maximumMenuHeight
                    && candidate.minX >= codexBounds.minX - 8
                    && candidate.maxX <= codexBounds.minX + sidebarWidth + 8
                    && candidate.maxY >= minimumMenuBottom
                    && candidate.minY < codexBounds.maxY - 80
            }
            .max { lhs, rhs in
                lhs.width * lhs.height < rhs.width * rhs.height
            }
        guard let menu, menu.height < codexBounds.height * 0.5 else { return menu }

        // ponytail: Codex AX omits the popup's 64pt header chrome; remove this when it exposes the full frame.
        let topInset = min(64, menu.minY - codexBounds.minY)
        return CGRect(
            x: menu.minX,
            y: menu.minY - topInset,
            width: menu.width,
            height: menu.height + topInset
        )
    }

    nonisolated static func sidebarWidth(
        candidates: [CGRect],
        codexBounds: CGRect
    ) -> CGFloat? {
        // ponytail: infer from edge-aligned AX groups until Codex exposes its sidebar splitter directly.
        let maximumWidth = min(codexBounds.width * 0.5, 500)
        return candidates
            .filter { candidate in
                abs(candidate.minX - codexBounds.minX) <= 4
                    && candidate.width >= 220
                    && candidate.width <= maximumWidth
                    && candidate.height >= 36
                    && candidate.minY >= codexBounds.minY
                    && candidate.maxY <= codexBounds.maxY
                    && (candidate.minY <= codexBounds.minY + 120
                        || candidate.maxY >= codexBounds.maxY - 8)
            }
            .map(\.width)
            .max()
    }

    nonisolated static func inferredSidebarWidth(forCodexWindowWidth width: CGFloat) -> CGFloat {
        // ponytail: responsive fallback for Codex builds that omit sidebar child geometry.
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
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.borderWidth = 0
        hostingView.layer?.shadowOpacity = 0

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
        panel.isMovableByWindowBackground = false
        panelMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard self?.settings?.codexSidebarQuotaOverlayIndependent == true else { return }
                panel?.saveFrame(usingName: "CodexQuotaOverlayIndependent")
            }
        }

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
        let enabled = settings?.showCodexSidebarQuotaOverlay == true
        let independent = settings?.codexSidebarQuotaOverlayIndependent == true
        let application = NSWorkspace.shared.frontmostApplication
        let isCodexFrontmost = application?.bundleIdentifier == Self.codexBundleIdentifier
        guard Self.shouldShowOverlay(
            enabled: enabled,
            independent: independent,
            hasAccessibilityPermission: hasAccessibilityPermission,
            isCodexFrontmost: isCodexFrontmost
        ) else {
            panel?.orderOut(nil)
            clearAccessibilityObservation()
            return
        }

        if independent {
            clearAccessibilityObservation()
            refreshIndependentPanelFrame()
            return
        }

        guard let application else { return }
        panel?.isMovableByWindowBackground = false
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
            kAXFocusedUIElementChangedNotification,
            kAXMainWindowChangedNotification,
            kAXLayoutChangedNotification,
            kAXMenuOpenedNotification,
            kAXMenuClosedNotification,
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
              let rawWindow = accessibilityAttribute(application, kAXMainWindowAttribute as CFString)
                ?? accessibilityAttribute(application, kAXFocusedWindowAttribute as CFString),
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
            kAXLayoutChangedNotification,
            kAXUIElementDestroyedNotification
        ].forEach { notification in
            AXObserverAddNotification(observer, window, notification as CFString, refcon)
        }
    }

    private func refreshPanelFrame() {
        if settings?.codexSidebarQuotaOverlayIndependent == true {
            refreshIndependentPanelFrame()
            return
        }
        guard settings?.showCodexSidebarQuotaOverlay == true,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier,
              let window = accessibilityWindow,
              accessibilityAttribute(window, kAXMinimizedAttribute as CFString) as? Bool != true,
              let position = accessibilityPoint(window, kAXPositionAttribute as CFString),
              let size = accessibilitySize(window, kAXSizeAttribute as CFString),
              let hostingView,
              let panel
        else {
            panel?.orderOut(nil)
            return
        }

        let codexBounds = CGRect(origin: position, size: size)
        lastCodexBounds = codexBounds
        guard let mainScreenMaxY = appKitCoordinateMaxY(for: codexBounds) else {
            panel.orderOut(nil)
            return
        }
        let candidates = accessibilityCandidateBounds(in: window)
        let sidebarWidth = Self.sidebarWidth(candidates: candidates, codexBounds: codexBounds)
            ?? Self.inferredSidebarWidth(forCodexWindowWidth: size.width)
        let accountMenuBounds = Self.accountMenuBounds(
            candidates: candidates,
            codexBounds: codexBounds,
            sidebarWidth: sidebarWidth
        )
        hostingView.frame.size.width = sidebarWidth - 24
        hostingView.layoutSubtreeIfNeeded()
        let contentHeight = max(1, ceil(hostingView.fittingSize.height))
        guard let frame = Self.panelFrame(
            codexBounds: codexBounds,
            sidebarWidth: sidebarWidth,
            accountMenuBounds: accountMenuBounds,
            contentHeight: contentHeight,
            mainScreenMaxY: mainScreenMaxY
        ) else {
            panel.orderOut(nil)
            return
        }

        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func pollAttachedPanelFrame() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier,
              let window = accessibilityWindow,
              let position = accessibilityPoint(window, kAXPositionAttribute as CFString),
              let size = accessibilitySize(window, kAXSizeAttribute as CFString)
        else { return }
        framePollCount += 1
        if CGRect(origin: position, size: size) != lastCodexBounds || framePollCount.isMultiple(of: 4) {
            refreshPanelFrame()
        }
    }

    private func refreshIndependentPanelFrame() {
        guard settings?.showCodexSidebarQuotaOverlay == true,
              let hostingView,
              let panel
        else {
            panel?.orderOut(nil)
            return
        }

        let enteringIndependentMode = !panel.isMovableByWindowBackground
        panel.isMovableByWindowBackground = true
        if enteringIndependentMode {
            _ = panel.setFrameUsingName("CodexQuotaOverlayIndependent")
        }

        let width: CGFloat = 280
        hostingView.frame.size.width = width
        hostingView.layoutSubtreeIfNeeded()
        let height = max(1, ceil(hostingView.fittingSize.height))
        var frame = panel.frame
        if frame.width <= 1 || frame.height <= 1 {
            let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
            frame = CGRect(x: visibleFrame.maxX - width - 24, y: visibleFrame.maxY - height - 24, width: width, height: height)
        } else {
            frame.origin.y = frame.maxY - height
            frame.size = CGSize(width: width, height: height)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func appKitCoordinateMaxY(for codexBounds: CGRect) -> CGFloat? {
        let displays = NSScreen.screens.compactMap { screen -> CodexDisplayGeometry? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return CodexDisplayGeometry(
                accessibilityFrame: CGDisplayBounds(CGDirectDisplayID(number.uint32Value)),
                appKitFrame: screen.frame
            )
        }
        return Self.appKitCoordinateMaxY(for: codexBounds, displays: displays)
    }

    private func clearAccessibilityObservation() {
        removeWindowNotifications()
        if let observer = accessibilityObserver, let application = accessibilityApplication {
            [
                kAXFocusedWindowChangedNotification,
                kAXFocusedUIElementChangedNotification,
                kAXMainWindowChangedNotification,
                kAXLayoutChangedNotification,
                kAXMenuOpenedNotification,
                kAXMenuClosedNotification,
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
        lastCodexBounds = nil
        framePollCount = 0
    }

    private func removeWindowNotifications() {
        guard let observer = accessibilityObserver, let window = accessibilityWindow else { return }
        [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXLayoutChangedNotification,
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

    private func accessibilityCandidateBounds(in mainWindow: AXUIElement) -> [CGRect] {
        var candidates: [CGRect] = []

        if let application = accessibilityApplication,
           let windows = accessibilityAttribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] {
            for window in windows where !CFEqual(window, mainWindow) {
                if let position = accessibilityPoint(window, kAXPositionAttribute as CFString),
                   let size = accessibilitySize(window, kAXSizeAttribute as CFString) {
                    candidates.append(CGRect(origin: position, size: size))
                }
            }
        }

        var inspectedElementCount = 0
        collectCandidateBounds(
            from: mainWindow,
            depth: 0,
            inspectedElementCount: &inspectedElementCount,
            candidates: &candidates
        )
        return candidates
    }

    private func collectCandidateBounds(
        from element: AXUIElement,
        depth: Int,
        inspectedElementCount: inout Int,
        candidates: inout [CGRect]
    ) {
        guard depth < 32, inspectedElementCount < 8_000 else { return }
        inspectedElementCount += 1

        if let position = accessibilityPoint(element, kAXPositionAttribute as CFString),
           let size = accessibilitySize(element, kAXSizeAttribute as CFString) {
            candidates.append(CGRect(origin: position, size: size))
        }

        guard let children = accessibilityAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return
        }
        for child in children {
            collectCandidateBounds(
                from: child,
                depth: depth + 1,
                inspectedElementCount: &inspectedElementCount,
                candidates: &candidates
            )
        }
    }
}
