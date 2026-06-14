import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private let settings: SettingsStore
    private let store: UsageStore
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        let settings = SettingsStore()
        self.settings = settings
        self.store = UsageStore(settings: settings)
        super.init()
    }

    func show() {
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            self.item = item
        }

        updateButton()
        bindStore()
    }

    private func bindStore() {
        guard cancellables.isEmpty else { return }
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
        guard let button = item?.button else { return }
        let image = AppLogo.menuBarImage().copy() as? NSImage ?? AppLogo.menuBarImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        button.image = image
        let title = store.menuBarTitle
        button.title = " \(title)"
        button.imagePosition = .imageLeading
        button.toolTip = "AgentBar \(title)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
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
            preferredHeight: CGFloat(settings.popoverHeight),
            maximumHeight: maximumHeight
        )

        let popover = NSPopover()
        let content = ResizablePopoverRootView(
            store: store,
            maximumHeight: maximumHeight,
            onOpenStatistics: { MainWindowPresenter.showMainWindow() },
            onOpenSettings: { MainWindowPresenter.showMainWindow(initialTab: .settings) },
            onHeightChange: { [weak popover] height in
                popover?.contentSize = NSSize(
                    width: PopoverLayout.width,
                    height: height
                )
            }
        )

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(
            width: PopoverLayout.width,
            height: height
        )
        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        sender.highlight(true)
        self.popover = popover
        refreshPopoverLayout(height: height)
    }

    private func refreshPopoverLayout(height: CGFloat) {
        guard let popover else { return }
        let size = NSSize(width: PopoverLayout.width, height: height)
        popover.contentSize = size
        popover.contentViewController?.view.needsLayout = true
        popover.contentViewController?.view.layoutSubtreeIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self, let popover = self.popover, popover.isShown else { return }
            popover.contentSize = size
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
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
