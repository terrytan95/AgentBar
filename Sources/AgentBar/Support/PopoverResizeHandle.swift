import AppKit
import SwiftUI

struct PopoverResizeHandle: NSViewRepresentable {
    var startHeight: CGFloat
    var minHeight: CGFloat = PopoverLayout.minimumHeight
    var maxHeight: CGFloat = PopoverLayout.maximumHeight
    var onHeightChange: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> PopoverResizeHandleView {
        let view = PopoverResizeHandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: PopoverResizeHandleView, context: Context) {
        nsView.startHeight = startHeight
        nsView.minHeight = minHeight
        nsView.maxHeight = maxHeight
        nsView.onHeightChange = onHeightChange
    }
}

final class PopoverResizeHandleView: NSView {
    private static let minimumIntermediateDelta: CGFloat = 2

    var startHeight: CGFloat = PopoverLayout.defaultHeight
    var minHeight: CGFloat = PopoverLayout.minimumHeight
    var maxHeight: CGFloat = PopoverLayout.maximumHeight
    var onHeightChange: ((CGFloat, Bool) -> Void)?

    private var dragStartHeight: CGFloat?
    private var dragStartScreenY: CGFloat?
    private var lastEmittedHeight: CGFloat?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartHeight = startHeight
        dragStartScreenY = NSEvent.mouseLocation.y
        lastEmittedHeight = nil
    }

    override func mouseDragged(with event: NSEvent) {
        updateHeight(isFinal: false)
    }

    override func mouseUp(with event: NSEvent) {
        updateHeight(isFinal: true)
        dragStartHeight = nil
        dragStartScreenY = nil
    }

    private func updateHeight(isFinal: Bool) {
        guard let dragStartHeight, let dragStartScreenY else { return }
        let translation = dragStartScreenY - NSEvent.mouseLocation.y
        let nextHeight = min(max(dragStartHeight + translation, minHeight), maxHeight)
        guard isFinal ||
            lastEmittedHeight.map({ abs($0 - nextHeight) >= Self.minimumIntermediateDelta }) ?? true
        else { return }
        lastEmittedHeight = nextHeight
        onHeightChange?(nextHeight, isFinal)
    }
}
