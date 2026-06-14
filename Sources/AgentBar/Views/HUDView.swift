import AppKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 14) {
            Label("AgentBar", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(DisplayFormatters.percentString(store.lowestRemaining)) \(L.text("remaining", store.language))")
                    .font(.title3.weight(.semibold))
                Text("\(DisplayFormatters.tokenString(store.summary.totalTokens)) \(L.text("tokens", store.language))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 360, height: 76)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .gesture(
            DragGesture()
                .onChanged { HUDWindowController.shared.move(by: $0.translation) }
                .onEnded { _ in HUDWindowController.shared.snapToNearestEdge() }
        )
    }
}

@MainActor
final class HUDWindowController {
    static let shared = HUDWindowController()

    private var panel: NSPanel?
    private var lastTranslation = CGSize.zero

    func show(store: UsageStore) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 900, width: 360, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: HUDView(store: store))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
    }

    func move(by translation: CGSize) {
        guard let panel else { return }
        let dx = translation.width - lastTranslation.width
        let dy = translation.height - lastTranslation.height
        var frame = panel.frame
        frame.origin.x += dx
        frame.origin.y -= dy
        panel.setFrame(frame, display: true)
        lastTranslation = translation
    }

    func snapToNearestEdge() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        lastTranslation = .zero
        var frame = panel.frame
        let visible = screen.visibleFrame
        let leftDistance = abs(frame.minX - visible.minX)
        let rightDistance = abs(visible.maxX - frame.maxX)
        frame.origin.x = leftDistance < rightDistance ? visible.minX + 12 : visible.maxX - frame.width - 12
        frame.origin.y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - frame.height - 12)
        panel.setFrame(frame, display: true, animate: true)
    }
}
