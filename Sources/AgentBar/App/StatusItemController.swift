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
        let title = store.isRefreshing ? L.text("refreshing", store.language) : store.menuBarTitle
        button.title = " \(title)"
        button.imagePosition = .imageLeading
        button.toolTip = "AgentBar \(title)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover?.isShown == true {
            popover?.performClose(sender)
            return
        }

        let content = PopoverRootView(
            store: store,
            onOpenStatistics: { MainWindowPresenter.showMainWindow() },
            onOpenSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
        )
        .frame(
            width: PopoverLayout.width,
            height: PopoverLayout.height(
                accountCount: store.accounts.count,
                sourceCount: store.uiDataSourceSnapshots.count
            )
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(
            width: PopoverLayout.width,
            height: PopoverLayout.height(
                accountCount: store.accounts.count,
                sourceCount: store.uiDataSourceSnapshots.count
            )
        )
        popover.contentViewController = NSHostingController(rootView: content)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        self.popover = popover
    }
}
