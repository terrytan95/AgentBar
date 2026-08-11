import AppKit
import ApplicationServices
import Combine
import os
import SwiftUI

struct CodexDisplayGeometry {
    var accessibilityFrame: CGRect
    var appKitFrame: CGRect
}

private struct CodexAccessibilityCandidate: @unchecked Sendable {
    var element: AXUIElement
    var bounds: CGRect
}

private struct CodexAccessibilityScanResult: @unchecked Sendable {
    var candidates: [CodexAccessibilityCandidate]
    var inspectedElementCount: Int
}

private struct CodexAccessibilityScanInput: @unchecked Sendable {
    var application: AXUIElement?
    var window: AXUIElement
}

private enum CodexOverlayFrameRefreshReason: String {
    case initial
    case accessibility
    case cardContent
    case fallback
}

private func codexSidebarQuotaAXCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let controller = Unmanaged<CodexSidebarQuotaOverlayController>.fromOpaque(refcon).takeUnretainedValue()
    let notificationName = notification as String
    Task { @MainActor in
        controller.handleAccessibilityChange(notification: notificationName)
    }
}

private final class CodexSidebarQuotaHostingView: NSHostingView<CodexSidebarQuotaCard>, NSGestureRecognizerDelegate {
    private static let resizeEdgeWidth: CGFloat = 5
    private var resizeTrackingArea: NSTrackingArea?
    private var isShowingResizeCursor = false
    private var windowDragRecognizer: NSPanGestureRecognizer?
    private var windowDragStartOrigin: NSPoint?
    private var windowDragStartMouseLocation: NSPoint?
    var allowsWindowDragging = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard windowDragRecognizer == nil else { return }
        let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handleWindowDrag(_:)))
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
        windowDragRecognizer = recognizer
    }

    override func updateTrackingAreas() {
        if let resizeTrackingArea {
            removeTrackingArea(resizeTrackingArea)
        }
        super.updateTrackingAreas()

        let resizeTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(resizeTrackingArea)
        self.resizeTrackingArea = resizeTrackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let x = convert(event.locationInWindow, from: nil).x
        let isResizeEdge = window?.styleMask.contains(.resizable) == true
            && (x <= Self.resizeEdgeWidth || x >= bounds.maxX - Self.resizeEdgeWidth)
        guard isResizeEdge != isShowingResizeCursor else { return }

        isShowingResizeCursor = isResizeEdge
        (isResizeEdge ? NSCursor.resizeLeftRight : .arrow).set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard isShowingResizeCursor else { return }
        isShowingResizeCursor = false
        NSCursor.arrow.set()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard allowsWindowDragging else { return false }
        let x = gestureRecognizer.location(in: self).x
        return x > Self.resizeEdgeWidth && x < bounds.maxX - Self.resizeEdgeWidth
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleWindowDrag(_ recognizer: NSPanGestureRecognizer) {
        guard let window, allowsWindowDragging else {
            windowDragStartOrigin = nil
            windowDragStartMouseLocation = nil
            return
        }
        switch recognizer.state {
        case .began:
            windowDragStartOrigin = window.frame.origin
            let translation = recognizer.translation(in: nil)
            let mouseLocation = NSEvent.mouseLocation
            windowDragStartMouseLocation = NSPoint(
                x: mouseLocation.x - translation.x,
                y: mouseLocation.y - translation.y
            )
        case .changed:
            guard let windowDragStartOrigin, let windowDragStartMouseLocation else { return }
            let mouseLocation = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(
                x: windowDragStartOrigin.x + mouseLocation.x - windowDragStartMouseLocation.x,
                y: windowDragStartOrigin.y + mouseLocation.y - windowDragStartMouseLocation.y
            ))
        case .ended, .cancelled, .failed:
            windowDragStartOrigin = nil
            windowDragStartMouseLocation = nil
        default:
            break
        }
    }
}

@MainActor
final class CodexSidebarQuotaOverlayController: ObservableObject {
    static let shared = CodexSidebarQuotaOverlayController()
    static let codexBundleIdentifier = "com.openai.codex"
    private static let minimumFrameFallbackInterval: TimeInterval = 5
    private static let maximumFrameFallbackInterval: TimeInterval = 300
    private static let fullScanCooldown: TimeInterval = 1
    private static let performanceLog = OSLog(
        subsystem: "com.terrytan.AgentBar",
        category: .pointsOfInterest
    )

    @Published private(set) var hasAccessibilityPermission = AXIsProcessTrusted()

    private weak var settings: SettingsStore?
    private var panel: NSPanel?
    private var hostingView: CodexSidebarQuotaHostingView?
    private var cardModel: CodexSidebarQuotaCardViewModel?
    private var panelMoveObserver: NSObjectProtocol?
    private var panelResizeObserver: NSObjectProtocol?
    private var frameRefreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityObserver: AXObserver?
    private var accessibilityApplication: AXUIElement?
    private var accessibilityWindow: AXUIElement?
    private var cachedSidebarElement: AXUIElement?
    private var cachedSidebarWidth: CGFloat?
    private var cachedAccountMenuElement: AXUIElement?
    private var lastCodexBounds: CGRect?
    private var lastFullScanUptime: TimeInterval?
    private var codexProcessIdentifier: pid_t?
    private var accessibilityRefreshTask: Task<Void, Never>?
    private var accessibilityScanTask: Task<Void, Never>?
    private var accessibilityScanWorkerTask: Task<CodexAccessibilityScanResult, Never>?
    private var accessibilityScanGeneration = 0
    private var frameFallbackInterval = CodexSidebarQuotaOverlayController.minimumFrameFallbackInterval
    private var isStarted = false

    func start(settings: SettingsStore, store: UsageStore) {
        guard !isStarted else { return }
        isStarted = true
        self.settings = settings
        let cardContent = Self.cardContent(accounts: store.accounts, language: settings.language)
        configurePanel(content: cardContent, settings: settings, store: store)
        observeWorkspace()

        settings.$showCodexSidebarQuotaOverlay
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVisibility()
                }
            }
            .store(in: &cancellables)

        settings.$codexSidebarQuotaOverlayIndependent
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVisibility()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(store.accountsPublisher, settings.$language)
            .map(Self.cardContent(accounts:language:))
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] content in
                Task { @MainActor in
                    self?.cardModel?.update(content)
                    await Task.yield()
                    self?.refreshPanelFrame(reason: .cardContent)
                }
            }
            .store(in: &cancellables)

        refreshVisibility()
    }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        if let panelMoveObserver {
            NotificationCenter.default.removeObserver(panelMoveObserver)
        }
        panelMoveObserver = nil
        if let panelResizeObserver {
            NotificationCenter.default.removeObserver(panelResizeObserver)
        }
        panelResizeObserver = nil
        frameRefreshTimer?.invalidate()
        frameRefreshTimer = nil
        cancellables.removeAll()
        clearAccessibilityObservation()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        cardModel = nil
        settings = nil
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
        guard let menu = accountMenuCandidateBounds(
            candidates: candidates,
            codexBounds: codexBounds,
            sidebarWidth: sidebarWidth
        ) else { return nil }
        return expandedAccountMenuBounds(menu, codexBounds: codexBounds)
    }

    private nonisolated static func accountMenuCandidateBounds(
        candidates: [CGRect],
        codexBounds: CGRect,
        sidebarWidth: CGFloat? = nil
    ) -> CGRect? {
        let sidebarWidth = sidebarWidth ?? inferredSidebarWidth(forCodexWindowWidth: codexBounds.width)
        let minimumMenuBottom = codexBounds.maxY - 160
        let maximumMenuHeight = codexBounds.height * 0.65

        return candidates
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
    }

    private nonisolated static func expandedAccountMenuBounds(
        _ menu: CGRect,
        codexBounds: CGRect
    ) -> CGRect {
        guard menu.height < codexBounds.height * 0.5 else { return menu }
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
        sidebarCandidateBounds(candidates: candidates, codexBounds: codexBounds)?.width
    }

    private nonisolated static func sidebarCandidateBounds(
        candidates: [CGRect],
        codexBounds: CGRect
    ) -> CGRect? {
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
            .max { lhs, rhs in lhs.width < rhs.width }
    }

    nonisolated static func inferredSidebarWidth(forCodexWindowWidth width: CGFloat) -> CGFloat {
        // ponytail: responsive fallback for Codex builds that omit sidebar child geometry.
        min(max(width * 0.35, 240), 360)
    }

    private nonisolated static func cardContent(
        accounts: [UsageAccount],
        language: AppLanguage
    ) -> CodexSidebarQuotaCardContent {
        let account = accounts.first { $0.service == .codex && $0.isActive }
            ?? accounts.first { $0.service == .codex }
        return CodexSidebarQuotaCardContent(account: account, language: language)
    }

    func handleAccessibilityChange(notification: String) {
        let refreshesWindow = notification == kAXFocusedWindowChangedNotification as String
            || notification == kAXMainWindowChangedNotification as String
            || notification == kAXWindowCreatedNotification as String
            || notification == kAXUIElementDestroyedNotification as String
        let isLayoutChange = notification == kAXLayoutChangedNotification as String
        let alwaysRequiresFullScan = refreshesWindow
            || notification == kAXMenuOpenedNotification as String
            || notification == kAXMenuClosedNotification as String

        accessibilityRefreshTask?.cancel()
        accessibilityRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 75_000_000)
            guard !Task.isCancelled, let self else { return }
            if notification == kAXUIElementDestroyedNotification as String {
                removeWindowNotifications()
                accessibilityWindow = nil
            }
            if refreshesWindow {
                refreshFocusedWindowObservation()
            }
            let scannedRecently = lastFullScanUptime.map {
                ProcessInfo.processInfo.systemUptime - $0 < Self.fullScanCooldown
            } ?? false
            let requiresFullScan = alwaysRequiresFullScan
                || (isLayoutChange && !scannedRecently)
                || (notification == kAXResizedNotification as String && cachedSidebarElement == nil)
            if requiresFullScan {
                invalidateCachedGeometry()
            }
            refreshPanelFrame(forceFullScan: requiresFullScan, reason: .accessibility)
            scheduleFrameFallback(reset: true)
        }
    }

    private func configurePanel(
        content: CodexSidebarQuotaCardContent,
        settings: SettingsStore,
        store: UsageStore
    ) {
        let cardModel = CodexSidebarQuotaCardViewModel(content: content)
        let card = CodexSidebarQuotaCard(
            model: cardModel,
            onShowMainWindow: { [weak store] in
                guard let store else { return }
                AgentBarWindowPresenter.presentStatisticsWindow(store: store, initialTab: .usage)
            },
            onCloseQuotaWindow: { [weak settings] in
                settings?.showCodexSidebarQuotaOverlay = false
            },
            onContentSizeChange: { [weak self] in
                Task { @MainActor in
                    await Task.yield()
                    self?.refreshPanelFrame(reason: .cardContent)
                }
            }
        )
        let hostingView = CodexSidebarQuotaHostingView(rootView: card)
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
                panel?.saveFrame(usingName: "CodexQuotaOverlayIndependentResizable")
            }
        }
        panelResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard self?.settings?.codexSidebarQuotaOverlayIndependent == true else { return }
                panel?.saveFrame(usingName: "CodexQuotaOverlayIndependentResizable")
            }
        }

        self.cardModel = cardModel
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

    func toggleVisibility() {
        settings?.showCodexSidebarQuotaOverlay.toggle()
        refreshVisibility()
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
            frameRefreshTimer?.invalidate()
            frameRefreshTimer = nil
            panel?.orderOut(nil)
            clearAccessibilityObservation()
            return
        }

        if independent {
            frameRefreshTimer?.invalidate()
            frameRefreshTimer = nil
            clearAccessibilityObservation()
            refreshIndependentPanelFrame()
            return
        }

        guard let application else { return }
        hostingView?.allowsWindowDragging = false
        panel?.isMovableByWindowBackground = false
        attach(to: application)
        refreshPanelFrame(forceFullScan: true, reason: .initial)
        scheduleFrameFallback(reset: true)
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
              let rawWindow = Self.accessibilityAttribute(application, kAXMainWindowAttribute as CFString)
                ?? Self.accessibilityAttribute(application, kAXFocusedWindowAttribute as CFString),
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

    private func refreshPanelFrame(
        forceFullScan: Bool = false,
        reason: CodexOverlayFrameRefreshReason
    ) {
        if settings?.codexSidebarQuotaOverlayIndependent == true {
            refreshIndependentPanelFrame()
            return
        }
        hostingView?.allowsWindowDragging = false
        panel?.styleMask.remove(.resizable)
        if let panel, let hostingView {
            panel.invalidateCursorRects(for: hostingView)
        }
        panel?.contentMinSize = .zero
        panel?.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        guard settings?.showCodexSidebarQuotaOverlay == true,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier,
              let window = accessibilityWindow,
              Self.accessibilityAttribute(window, kAXMinimizedAttribute as CFString) as? Bool != true,
              let position = Self.accessibilityPoint(window, kAXPositionAttribute as CFString),
              let size = Self.accessibilitySize(window, kAXSizeAttribute as CFString),
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

        var needsFullScan = forceFullScan || cachedSidebarWidth == nil
        var sidebarWidth = cachedSidebarWidth
        var accountMenuBounds: CGRect?
        if !needsFullScan, let cachedSidebarElement {
            if let bounds = Self.accessibilityBounds(cachedSidebarElement) {
                sidebarWidth = bounds.width
                cachedSidebarWidth = bounds.width
            } else {
                needsFullScan = true
            }
        }
        if !needsFullScan, let cachedAccountMenuElement {
            if let bounds = Self.accessibilityBounds(cachedAccountMenuElement) {
                accountMenuBounds = Self.expandedAccountMenuBounds(bounds, codexBounds: codexBounds)
            } else {
                needsFullScan = true
            }
        }

        if needsFullScan {
            startAccessibilityScan(in: window, codexBounds: codexBounds, reason: reason)
            return
        }

        guard let sidebarWidth else {
            panel.orderOut(nil)
            return
        }
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

        let frameChanged = panel.frame != frame
        os_signpost(
            .event,
            log: Self.performanceLog,
            name: "Overlay frame",
            "reason=%{public}@ changed=%{public}d",
            reason.rawValue,
            frameChanged ? 1 : 0
        )
        if frameChanged {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func startAccessibilityScan(
        in window: AXUIElement,
        codexBounds: CGRect,
        reason: CodexOverlayFrameRefreshReason
    ) {
        guard accessibilityScanTask == nil else { return }
        let input = CodexAccessibilityScanInput(
            application: accessibilityApplication,
            window: window
        )
        let generation = accessibilityScanGeneration
        let signpostID = OSSignpostID(log: Self.performanceLog)
        lastFullScanUptime = ProcessInfo.processInfo.systemUptime
        os_signpost(
            .begin,
            log: Self.performanceLog,
            name: "AX tree scan",
            signpostID: signpostID,
            "reason=%{public}@",
            reason.rawValue
        )

        let workerTask = Task.detached(priority: .utility) {
            Self.accessibilityCandidates(application: input.application, in: input.window)
        }
        accessibilityScanWorkerTask = workerTask
        accessibilityScanTask = Task { @MainActor [weak self] in
            let scan = await workerTask.value
            os_signpost(
                .end,
                log: Self.performanceLog,
                name: "AX tree scan",
                signpostID: signpostID,
                "nodes=%{public}d",
                scan.inspectedElementCount
            )
            guard let self else { return }
            if accessibilityScanGeneration == generation {
                accessibilityScanTask = nil
                accessibilityScanWorkerTask = nil
            }
            guard !Task.isCancelled,
                  accessibilityScanGeneration == generation,
                  let currentWindow = accessibilityWindow,
                  CFEqual(currentWindow, window)
            else { return }

            let candidates = scan.candidates.map(\.bounds)
            let sidebarBounds = Self.sidebarCandidateBounds(candidates: candidates, codexBounds: codexBounds)
            let sidebarWidth = sidebarBounds?.width
                ?? Self.inferredSidebarWidth(forCodexWindowWidth: codexBounds.width)
            cachedSidebarWidth = sidebarWidth
            cachedSidebarElement = sidebarBounds.flatMap { bounds in
                scan.candidates.first { $0.bounds == bounds }?.element
            }
            let accountMenuBounds = Self.accountMenuCandidateBounds(
                candidates: candidates,
                codexBounds: codexBounds,
                sidebarWidth: sidebarWidth
            )
            cachedAccountMenuElement = accountMenuBounds.flatMap { bounds in
                scan.candidates.first { $0.bounds == bounds }?.element
            }
            refreshPanelFrame(reason: reason)
        }
    }

    private func scheduleFrameFallback(reset: Bool) {
        frameRefreshTimer?.invalidate()
        frameRefreshTimer = nil
        if reset {
            frameFallbackInterval = Self.minimumFrameFallbackInterval
        }
        guard isStarted,
              settings?.showCodexSidebarQuotaOverlay == true,
              settings?.codexSidebarQuotaOverlayIndependent == false,
              panel?.isVisible == true
        else { return }

        let timer = Timer(timeInterval: frameFallbackInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runFrameFallback()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameRefreshTimer = timer
    }

    private func runFrameFallback() {
        frameRefreshTimer = nil
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier,
              let window = accessibilityWindow,
              let position = Self.accessibilityPoint(window, kAXPositionAttribute as CFString),
              let size = Self.accessibilitySize(window, kAXSizeAttribute as CFString)
        else { return }
        let codexBounds = CGRect(origin: position, size: size)
        let watchdogExpired = frameFallbackInterval >= Self.maximumFrameFallbackInterval
        if codexBounds != lastCodexBounds || watchdogExpired {
            refreshPanelFrame(forceFullScan: watchdogExpired, reason: .fallback)
        }
        frameFallbackInterval = min(frameFallbackInterval * 2, Self.maximumFrameFallbackInterval)
        scheduleFrameFallback(reset: false)
    }

    private func refreshIndependentPanelFrame() {
        guard settings?.showCodexSidebarQuotaOverlay == true,
              let hostingView,
              let panel
        else {
            panel?.orderOut(nil)
            return
        }

        let enteringIndependentMode = !hostingView.allowsWindowDragging
        hostingView.allowsWindowDragging = true
        panel.isMovableByWindowBackground = false
        panel.styleMask.insert(.resizable)
        panel.invalidateCursorRects(for: hostingView)
        if enteringIndependentMode {
            _ = panel.setFrameUsingName("CodexQuotaOverlayIndependentResizable")
        }

        let width = min(max(panel.frame.width > 1 ? panel.frame.width : 264, 220), 420)
        hostingView.frame.size.width = width
        hostingView.layoutSubtreeIfNeeded()
        let height = max(1, ceil(hostingView.fittingSize.height))
        panel.contentMinSize = NSSize(width: 220, height: height)
        panel.contentMaxSize = NSSize(width: 420, height: height)
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
        accessibilityRefreshTask?.cancel()
        accessibilityRefreshTask = nil
        frameRefreshTimer?.invalidate()
        frameRefreshTimer = nil
        removeWindowNotifications()
        if let observer = accessibilityObserver, let application = accessibilityApplication {
            [
                kAXFocusedWindowChangedNotification,
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
        invalidateCachedGeometry()
        lastCodexBounds = nil
        lastFullScanUptime = nil
        frameFallbackInterval = Self.minimumFrameFallbackInterval
    }

    private func invalidateCachedGeometry() {
        cancelAccessibilityScan()
        cachedSidebarElement = nil
        cachedSidebarWidth = nil
        cachedAccountMenuElement = nil
    }

    private func cancelAccessibilityScan() {
        accessibilityScanGeneration &+= 1
        accessibilityScanTask?.cancel()
        accessibilityScanTask = nil
        accessibilityScanWorkerTask?.cancel()
        accessibilityScanWorkerTask = nil
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

    private nonisolated static func accessibilityAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private nonisolated static func accessibilityPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        guard let rawValue = accessibilityAttribute(element, attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private nonisolated static func accessibilitySize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let rawValue = accessibilityAttribute(element, attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private nonisolated static func accessibilityBounds(_ element: AXUIElement) -> CGRect? {
        guard let position = accessibilityPoint(element, kAXPositionAttribute as CFString),
              let size = accessibilitySize(element, kAXSizeAttribute as CFString)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private nonisolated static func accessibilityCandidates(
        application: AXUIElement?,
        in mainWindow: AXUIElement
    ) -> CodexAccessibilityScanResult {
        var candidates: [CodexAccessibilityCandidate] = []
        var inspectedElementCount = 0

        if let application,
           let windows = accessibilityAttribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] {
            for window in windows where !Task.isCancelled && !CFEqual(window, mainWindow) {
                inspectedElementCount += 1
                if let bounds = accessibilityBounds(window) {
                    candidates.append(CodexAccessibilityCandidate(element: window, bounds: bounds))
                }
            }
        }

        collectCandidates(
            from: mainWindow,
            depth: 0,
            inspectedElementCount: &inspectedElementCount,
            candidates: &candidates
        )
        return CodexAccessibilityScanResult(
            candidates: candidates,
            inspectedElementCount: inspectedElementCount
        )
    }

    private nonisolated static func collectCandidates(
        from element: AXUIElement,
        depth: Int,
        inspectedElementCount: inout Int,
        candidates: inout [CodexAccessibilityCandidate]
    ) {
        guard !Task.isCancelled, depth < 32, inspectedElementCount < 8_000 else { return }
        inspectedElementCount += 1

        if let bounds = accessibilityBounds(element) {
            candidates.append(CodexAccessibilityCandidate(element: element, bounds: bounds))
        }

        guard let children = accessibilityAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return
        }
        for child in children {
            guard !Task.isCancelled else { return }
            collectCandidates(
                from: child,
                depth: depth + 1,
                inspectedElementCount: &inspectedElementCount,
                candidates: &candidates
            )
        }
    }
}
