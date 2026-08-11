import AppKit
import Carbon
import Combine
import SwiftUI

struct QuotaWidgetHotKey: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        guard carbonModifiers != 0 else { return nil }

        keyCode = UInt32(event.keyCode)
        modifiers = carbonModifiers
        keyLabel = Self.label(for: event)
    }

    var displayText: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    private static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }
}

@MainActor
final class QuotaWidgetHotKeyController: ObservableObject {
    static let shared = QuotaWidgetHotKeyController()

    @Published private(set) var registrationFailed = false

    private let hotKeyID = EventHotKeyID(signature: 0x41474252, id: 1)
    private weak var settings: SettingsStore?
    private var cancellable: AnyCancellable?
    private var eventHandler: EventHandlerRef?
    private var registeredHotKey: EventHotKeyRef?
    private var isRecorderActive = false

    func start(settings: SettingsStore) {
        guard self.settings == nil else { return }
        self.settings = settings
        installEventHandler()
        cancellable = settings.$quotaWidgetHotKey
            .removeDuplicates()
            .sink { [weak self] hotKey in
                guard self?.isRecorderActive == false else { return }
                self?.register(hotKey)
            }
    }

    func stop() {
        cancellable = nil
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        isRecorderActive = false
        settings = nil
    }

    func setRecorderActive(_ active: Bool) {
        guard active != isRecorderActive else { return }
        isRecorderActive = active
        if active {
            unregisterHotKey()
        } else {
            register(settings?.quotaWidgetHotKey)
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.id == 1 else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async {
                    CodexSidebarQuotaOverlayController.shared.toggleVisibility()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }

    private func register(_ hotKey: QuotaWidgetHotKey?) {
        unregisterHotKey()
        guard let hotKey else {
            registrationFailed = false
            return
        }

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )
        registrationFailed = status != noErr
    }

    private func unregisterHotKey() {
        if let registeredHotKey {
            UnregisterEventHotKey(registeredHotKey)
            self.registeredHotKey = nil
        }
    }
}

struct QuotaWidgetHotKeyRecorder: NSViewRepresentable {
    @Binding var hotKey: QuotaWidgetHotKey?
    var emptyText: String
    var recordingText: String

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.onChange = { hotKey = $0 }
        return button
    }

    func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
        button.hotKey = hotKey
        button.emptyText = emptyText
        button.recordingText = recordingText
        button.updateTitle()
    }
}

final class HotKeyRecorderButton: NSButton {
    var hotKey: QuotaWidgetHotKey?
    var emptyText = "Set Shortcut"
    var recordingText = "Type shortcut…"
    var onChange: ((QuotaWidgetHotKey?) -> Void)?
    private var isRecording = false
    private nonisolated(unsafe) var keyDownMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func beginRecording() {
        isRecording = true
        guard window?.makeFirstResponder(self) == true else {
            isRecording = false
            updateTitle()
            return
        }
        QuotaWidgetHotKeyController.shared.setRecorderActive(true)
        if keyDownMonitor == nil {
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.isRecording,
                      event.window === self.window
                else { return event }
                self.handleKeyDown(event)
                return nil
            }
        }
        updateTitle()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func stopRecording() {
        guard isRecording || keyDownMonitor != nil else { return }
        isRecording = false
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        QuotaWidgetHotKeyController.shared.setRecorderActive(false)
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        handleKeyDown(event)
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            hotKey = nil
            onChange?(nil)
            window?.makeFirstResponder(nil)
            return
        }
        guard let hotKey = QuotaWidgetHotKey(event: event) else {
            NSSound.beep()
            return
        }
        self.hotKey = hotKey
        onChange?(hotKey)
        window?.makeFirstResponder(nil)
    }

    func updateTitle() {
        title = isRecording ? recordingText : hotKey?.displayText ?? emptyText
        setAccessibilityLabel(title)
    }
}
