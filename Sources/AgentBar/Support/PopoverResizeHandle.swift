import AppKit
import SwiftUI

struct PopoverResizeHandle: NSViewRepresentable {
    var startHeight: CGFloat
    var resize: PopoverResizeDrag
    var onHeightChange: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> PopoverResizeHandleView {
        let view = PopoverResizeHandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: PopoverResizeHandleView, context: Context) {
        nsView.startHeight = startHeight
        nsView.resize = resize
        nsView.onHeightChange = onHeightChange
    }
}

final class PopoverResizeHandleView: NSView {
    var startHeight: CGFloat = PopoverLayout.defaultHeight
    var resize = PopoverResizeDrag(
        bounds: PanelResizeBounds(
            minHeight: Double(PopoverLayout.minimumHeight),
            maxHeight: Double(PopoverLayout.maximumHeight)
        )
    )
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
        let nextHeight = resize.height(
            startHeight: Double(dragStartHeight),
            startScreenY: Double(dragStartScreenY),
            currentScreenY: Double(NSEvent.mouseLocation.y)
        )
        guard PopoverResizeDrag.shouldEmit(
            previousHeight: lastEmittedHeight.map(Double.init),
            nextHeight: nextHeight,
            isFinal: isFinal
        ) else { return }
        lastEmittedHeight = CGFloat(nextHeight)
        onHeightChange?(CGFloat(nextHeight), isFinal)
    }
}
