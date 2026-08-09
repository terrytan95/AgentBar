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
        guard let button = item?.button, let settings, let store else { return }
        let menuBarImage = AppLogo.menuBarImage()
        let image = menuBarImage.copy() as? NSImage ?? menuBarImage
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        button.image = image
        let title = store.menuBarTitle
        let showsProviderStatus = settings.showOtherServiceStatusInMenuBar
        let enabledServices = Set(store.menuBarEnabledServices)
        let highlighted = popover?.isShown == true
        let foregroundColor = highlighted ? NSColor.white : NSColor.labelColor
        let attributedTitle = NSMutableAttributedString(
            string: showsProviderStatus ? " \(title)  " : " \(title)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: foregroundColor
            ]
        )
        if showsProviderStatus {
            let attachment = NSTextAttachment()
            attachment.image = Self.providerBadgeImage(
                enabledServices: enabledServices,
                highlighted: highlighted
            )
            attachment.bounds = NSRect(x: 0, y: -4, width: 74, height: 18)
            attributedTitle.append(NSAttributedString(attachment: attachment))
        }
        button.attributedTitle = attributedTitle
        button.imagePosition = .imageLeading
        let providerNames = showsProviderStatus
            ? store.menuBarEnabledServices.map(\.rawValue).joined(separator: " · ")
            : ""
        button.toolTip = providerNames.isEmpty
            ? "AgentBar \(title)"
            : "AgentBar \(title)\n\(providerNames)"
        button.setAccessibilityLabel("AgentBar")
        button.setAccessibilityValue(
            providerNames.isEmpty
                ? title
                : "\(title), \(store.menuBarEnabledServices.count) providers: \(providerNames)"
        )
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
        updateButton()

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

    /// Matches `AgentBarApp` appearance policy: explicitly light or dark.
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
        updateButton()
    }

    private static func providerBadgeImage(
        enabledServices: Set<UsageService>,
        highlighted: Bool
    ) -> NSImage {
        let size = NSSize(width: 74, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let foreground = highlighted ? NSColor.white : NSColor.labelColor
            foreground.withAlphaComponent(highlighted ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

            var x: CGFloat = 5
            for service in UsageService.allCases {
                let iconRect = NSRect(x: x, y: 4, width: 10, height: 10)
                let iconColor = foreground.withAlphaComponent(enabledServices.contains(service) ? 0.95 : 0.22)
                tintedProviderImage(for: service, color: iconColor, size: iconRect.size)
                    .draw(in: iconRect)
                x += 13
            }

            foreground.withAlphaComponent(0.28).setFill()
            NSRect(x: 56, y: 4, width: 1, height: 10).fill()

            let count = NSAttributedString(
                string: "\(enabledServices.count)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: foreground.withAlphaComponent(0.95)
                ]
            )
            let countSize = count.size()
            count.draw(at: NSPoint(x: 62, y: (rect.height - countSize.height) / 2))
            return true
        }
    }

    private static func tintedProviderImage(
        for service: UsageService,
        color: NSColor,
        size: NSSize
    ) -> NSImage {
        let source = ProviderIcon.image(for: service)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        item?.button?.highlight(false)
        popover = nil
        updateButton()
    }
}
