import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var settings: SettingsStore?
    private var store: UsageStore?
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    func show(settings: SettingsStore, store: UsageStore) {
        self.settings = settings
        self.store = store
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
            self.item = item
        }

        updateButton()
        bindStore()
    }

    private func bindStore() {
        guard cancellables.isEmpty else { return }
        guard let settings, let store else { return }
        store.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateButton() }
            }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateButton() }
            }
            .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = item?.button, let store else { return }
        let menuBarImage = AppLogo.menuBarImage()
        let image = menuBarImage.copy() as? NSImage ?? menuBarImage
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        button.image = image
        let title = store.menuBarTitle
        button.title = " \(title)"
        button.imagePosition = .imageLeading
        button.toolTip = "AgentBar \(title)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let settings, let store else { return }
        if popover?.isShown == true {
            closePopover(sender)
            return
        }
        let maximumHeight = PopoverLayout.maximumHeight(
            forScreenHeight: sender.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height
        )
        settings.updatePopoverMaximumHeight(Double(maximumHeight))
        let height = PopoverLayout.height(
            accountCount: store.accounts.count,
            sourceCount: store.uiDataSourceSnapshots.count,
            maximumHeight: maximumHeight
        )
        settings.popoverHeight = Double(height)

        let popover = NSPopover()
        // Status-item popovers inherit the menu-bar appearance by default and ignore
        // NSApp.appearance; pin both AppKit chrome and SwiftUI color scheme explicitly.
        let appearance = Self.resolvedAppAppearance()
        let content = ResizablePopoverRootView(
            store: store,
            maximumHeight: maximumHeight,
            onQuit: { NSApplication.shared.terminate(nil) },
            onHeightChange: { [weak popover] height in
                popover?.contentSize = NSSize(
                    width: PopoverLayout.width,
                    height: height
                )
            }
        )
        .preferredColorScheme(Self.preferredColorScheme(for: appearance))

        popover.animates = false
        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = appearance
        popover.contentSize = NSSize(
            width: PopoverLayout.width,
            height: height
        )
        let hostingController = NSHostingController(rootView: content)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.appearance = appearance
        popover.contentViewController = hostingController
        self.popover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        sender.highlight(true)

        Self.applyPopoverAppearance(appearance, to: hostingController.view)
        if settings.useTranslucentAppearance {
            Self.applyLiquidGlassPopoverChrome(to: hostingController.view)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let popover = self.popover, popover.isShown else { return }
            popover.contentSize = NSSize(width: PopoverLayout.width, height: height)
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
            Self.applyPopoverAppearance(appearance, to: popover.contentViewController?.view)
            if settings.useTranslucentAppearance {
                Self.applyLiquidGlassPopoverChrome(to: popover.contentViewController?.view)
            }
        }
    }

    /// Matches `AgentBarApp` appearance policy: forced dark when enabled, otherwise system.
    private static func resolvedAppAppearance() -> NSAppearance {
        NSApp.appearance ?? NSApp.effectiveAppearance
    }

    private static func preferredColorScheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private static func applyPopoverAppearance(_ appearance: NSAppearance, to rootView: NSView?) {
        guard let rootView else { return }
        rootView.appearance = appearance
        rootView.window?.appearance = appearance
    }

    /// Clears NSPopover chrome so `agentBarGlassSurface` (behind-window material) can show through.
    private static func applyLiquidGlassPopoverChrome(to rootView: NSView?) {
        guard let rootView else { return }
        if let window = rootView.window {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }

        var current: NSView? = rootView
        while let view = current {
            view.wantsLayer = true
            if let effectView = view as? NSVisualEffectView {
                // Keep material sampling of desktop/content behind the popover window.
                effectView.blendingMode = .behindWindow
                effectView.state = .active
                effectView.isEmphasized = true
            } else {
                view.layer?.backgroundColor = NSColor.clear.cgColor
            }
            current = view.superview
        }
    }

    private func closePopover(_ sender: Any?) {
        popover?.performClose(sender)
        item?.button?.highlight(false)
        popover = nil
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        item?.button?.highlight(false)
        popover = nil
    }
}
