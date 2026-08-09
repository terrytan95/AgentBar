import AppKit
import SwiftUI

struct PopoverResizeHandle: NSViewRepresentable {
    enum Axis {
        case width
        case height
    }

    var axis: Axis = .height
    var startSize: CGFloat
    var minimumSize: CGFloat
    var maximumSize: CGFloat
    var onSizeChange: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> PopoverResizeHandleView {
        let view = PopoverResizeHandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: PopoverResizeHandleView, context: Context) {
        nsView.axis = axis
        nsView.startSize = startSize
        nsView.minimumSize = minimumSize
        nsView.maximumSize = maximumSize
        nsView.onSizeChange = onSizeChange
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

final class PopoverResizeHandleView: NSView {
    private static let minimumIntermediateDelta: CGFloat = 2
    private static let resizeInterval = 1.0 / 60.0

    var axis: PopoverResizeHandle.Axis = .height
    var startSize: CGFloat = PopoverLayout.defaultHeight
    var minimumSize: CGFloat = PopoverLayout.minimumHeight
    var maximumSize: CGFloat = PopoverLayout.maximumHeight
    var onSizeChange: ((CGFloat, Bool) -> Void)?

    private var dragStartSize: CGFloat?
    private var dragStartScreenPoint: NSPoint?
    private var lastEmittedSize: CGFloat?
    private var pendingSize: CGFloat?
    private var pendingResize: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .width ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        pendingResize?.cancel()
        pendingResize = nil
        pendingSize = nil
        dragStartSize = startSize
        dragStartScreenPoint = NSEvent.mouseLocation
        lastEmittedSize = nil
    }

    override func mouseDragged(with event: NSEvent) {
        updateSize(isFinal: false)
    }

    override func mouseUp(with event: NSEvent) {
        updateSize(isFinal: true)
        dragStartSize = nil
        dragStartScreenPoint = nil
    }

    private func updateSize(isFinal: Bool) {
        guard let dragStartSize, let dragStartScreenPoint else { return }
        let currentPoint = NSEvent.mouseLocation
        let translation = axis == .width
            ? currentPoint.x - dragStartScreenPoint.x
            : dragStartScreenPoint.y - currentPoint.y
        let nextSize = min(max(dragStartSize + translation, minimumSize), maximumSize)
        if isFinal {
            pendingResize?.cancel()
            pendingResize = nil
            pendingSize = nil
            lastEmittedSize = nextSize
            onSizeChange?(nextSize, true)
            return
        }
        guard lastEmittedSize.map({ abs($0 - nextSize) >= Self.minimumIntermediateDelta }) ?? true else {
            return
        }
        pendingSize = nextSize
        guard pendingResize == nil else { return }

        let resize = DispatchWorkItem { [weak self] in
            guard let self, let size = pendingSize else { return }
            pendingResize = nil
            pendingSize = nil
            lastEmittedSize = size
            onSizeChange?(size, false)
        }
        pendingResize = resize
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resizeInterval, execute: resize)
    }
}
