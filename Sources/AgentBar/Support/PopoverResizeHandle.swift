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
    private static let resizeInterval = 1.0 / 60.0

    var startHeight: CGFloat = PopoverLayout.defaultHeight
    var minHeight: CGFloat = PopoverLayout.minimumHeight
    var maxHeight: CGFloat = PopoverLayout.maximumHeight
    var onHeightChange: ((CGFloat, Bool) -> Void)?

    private var dragStartHeight: CGFloat?
    private var dragStartScreenY: CGFloat?
    private var lastEmittedHeight: CGFloat?
    private var pendingHeight: CGFloat?
    private var pendingResize: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        pendingResize?.cancel()
        pendingResize = nil
        pendingHeight = nil
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
        if isFinal {
            pendingResize?.cancel()
            pendingResize = nil
            pendingHeight = nil
            lastEmittedHeight = nextHeight
            onHeightChange?(nextHeight, true)
            return
        }
        guard lastEmittedHeight.map({ abs($0 - nextHeight) >= Self.minimumIntermediateDelta }) ?? true else {
            return
        }
        pendingHeight = nextHeight
        guard pendingResize == nil else { return }

        let resize = DispatchWorkItem { [weak self] in
            guard let self, let height = pendingHeight else { return }
            pendingResize = nil
            pendingHeight = nil
            lastEmittedHeight = height
            onHeightChange?(height, false)
        }
        pendingResize = resize
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resizeInterval, execute: resize)
    }
}
