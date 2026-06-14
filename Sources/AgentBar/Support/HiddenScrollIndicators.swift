import AppKit
import SwiftUI

struct HiddenScrollIndicators: NSViewRepresentable {
    func makeNSView(context: Context) -> HiddenScrollIndicatorsView {
        HiddenScrollIndicatorsView()
    }

    func updateNSView(_ nsView: HiddenScrollIndicatorsView, context: Context) {
        nsView.configureEnclosingScrollView()
    }
}

final class HiddenScrollIndicatorsView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.scrollerInsets = NSEdgeInsetsZero
            scrollView.contentInsets = NSEdgeInsetsZero
            scrollView.contentView.contentInsets = NSEdgeInsetsZero
            scrollView.verticalScroller?.isHidden = true
            scrollView.horizontalScroller?.isHidden = true
            scrollView.tile()
            scrollView.layoutSubtreeIfNeeded()
        }
    }
}
