import AppKit
import SwiftUI

struct PopoverScrollView<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> PopoverConfiguredScrollView {
        let scrollView = PopoverConfiguredScrollView()
        scrollView.setHostedContent(AnyView(content()))
        return scrollView
    }

    func updateNSView(_ scrollView: PopoverConfiguredScrollView, context: Context) {
        scrollView.updateHostedContent(AnyView(content()))
    }
}

final class PopoverConfiguredScrollView: NSScrollView {
    private var hostingView: NSHostingView<AnyView>?
    private var measuredContentWidth: CGFloat = 0
    private var measuredDocumentHeight: CGFloat = 1
    private var needsDocumentMeasurement = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        applyScrollConfiguration()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyScrollConfiguration()
    }

    func setHostedContent(_ content: AnyView) {
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        self.hostingView = hostingView
        documentView = hostingView
        needsDocumentMeasurement = true
        applyScrollConfiguration()
        refreshLayout()
    }

    func updateHostedContent(_ content: AnyView) {
        hostingView?.rootView = content
        needsDocumentMeasurement = true
        applyScrollConfiguration()
        refreshLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshLayout()
        scheduleDeferredLayoutPasses()
    }

    override func tile() {
        applyScrollConfiguration()
        super.tile()
        suppressScrollers()
        updateDocumentSize()
    }

    override func layout() {
        super.layout()
        suppressScrollers()
        updateDocumentSize()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        suppressScrollers()
        updateDocumentSize()
    }

    private func scheduleDeferredLayoutPasses() {
        guard window != nil else { return }
        for delay in [0.0, 0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshLayout()
            }
        }
    }

    private func refreshLayout() {
        applyScrollConfiguration()
        suppressScrollers()
        updateDocumentSize()
        tile()
        layoutSubtreeIfNeeded()
    }

    private func applyScrollConfiguration() {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = false
        scrollerStyle = .legacy
        automaticallyAdjustsContentInsets = false
        scrollerInsets = NSEdgeInsetsZero
        contentInsets = NSEdgeInsetsZero
        contentView.contentInsets = NSEdgeInsetsZero
        borderType = .noBorder
        drawsBackground = false
        backgroundColor = .clear
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .automatic
    }

    private func suppressScrollers() {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        verticalScroller?.isHidden = true
        horizontalScroller?.isHidden = true
        verticalScroller?.alphaValue = 0
        horizontalScroller?.alphaValue = 0
    }

    private func updateDocumentSize() {
        guard let hostingView else { return }

        let width = contentView.bounds.width
        guard width > 0 else { return }

        let widthChanged = abs(width - measuredContentWidth) >= 0.5
        if needsDocumentMeasurement || widthChanged {
            hostingView.setFrameSize(NSSize(width: width, height: 1))
            hostingView.layoutSubtreeIfNeeded()
            measuredContentWidth = width
            measuredDocumentHeight = max(hostingView.fittingSize.height, 1)
            needsDocumentMeasurement = false
        }

        let nextSize = NSSize(width: width, height: measuredDocumentHeight)

        if hostingView.frame.size != nextSize {
            hostingView.setFrameSize(nextSize)
        }
    }
}
