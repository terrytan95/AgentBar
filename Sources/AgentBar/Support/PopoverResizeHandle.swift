import AppKit
import SwiftUI

struct PopoverResizeHandle: NSViewRepresentable {
    enum Edge {
        case bottom
        case leading
        case trailing

        var cursor: NSCursor {
            self == .bottom ? .resizeUpDown : .resizeLeftRight
        }

        func translation(from start: NSPoint, to current: NSPoint) -> CGFloat {
            switch self {
            case .bottom:
                start.y - current.y
            case .leading:
                start.x - current.x
            case .trailing:
                current.x - start.x
            }
        }
    }

    var edge: Edge = .bottom
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
        nsView.edge = edge
        nsView.startSize = startSize
        nsView.minimumSize = minimumSize
        nsView.maximumSize = maximumSize
        nsView.onSizeChange = onSizeChange
    }
}

final class PopoverResizeHandleView: NSView {
    private static let minimumIntermediateDelta: CGFloat = 2
    private static let resizeInterval = 1.0 / 60.0

    var edge: PopoverResizeHandle.Edge = .bottom
    var startSize: CGFloat = PopoverLayout.defaultHeight
    var minimumSize: CGFloat = PopoverLayout.minimumHeight
    var maximumSize: CGFloat = PopoverLayout.maximumHeight
    var onSizeChange: ((CGFloat, Bool) -> Void)?

    private var dragStartSize: CGFloat?
    private var dragStartScreenPoint: NSPoint?
    private var lastEmittedSize: CGFloat?
    private var pendingSize: CGFloat?
    private var pendingResize: DispatchWorkItem?
    private var resizeTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

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

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        edge.cursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        edge.cursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if dragStartSize == nil {
            NSCursor.arrow.set()
        }
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
        if !bounds.contains(convert(event.locationInWindow, from: nil)) {
            NSCursor.arrow.set()
        }
    }

    private func updateSize(isFinal: Bool) {
        guard let dragStartSize, let dragStartScreenPoint else { return }
        let currentPoint = NSEvent.mouseLocation
        let translation = edge.translation(from: dragStartScreenPoint, to: currentPoint)
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
