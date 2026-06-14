import AppKit
import SwiftUI

struct LaunchStatusView: View {
    @StateObject private var store = UsageStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: AppLogo.image())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("AgentBar is running")
                        .font(.title3.weight(.semibold))
                    Text("Look for the AgentBar icon and quota percentage in the menu bar.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                KPIPill(title: L.text("lowest_remaining", store.language), value: DisplayFormatters.percentString(store.lowestRemaining), tint: .green)
                KPIPill(title: L.text("total_tokens", store.language), value: DisplayFormatters.tokenString(store.summary.totalTokens), tint: .blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.accounts.prefix(4)) { account in
                    HStack {
                        Text(account.displayName)
                            .lineLimit(1)
                        Spacer()
                        Text("\(L.text("five_hour", store.language)) \(DisplayFormatters.percentString(account.fiveHourWindow?.remainingPercent))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            HStack {
                Button {
                    HUDWindowController.shared.show(store: store)
                } label: {
                    Label(L.text("show_hud", store.language), systemImage: "rectangle.on.rectangle")
                }
                Button {
                    store.refresh()
                } label: {
                    Label(L.text("refresh", store.language), systemImage: "arrow.clockwise")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(.regularMaterial)
    }
}

@MainActor
final class LaunchStatusWindowController {
    static let shared = LaunchStatusWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentBar"
        window.center()
        window.contentView = NSHostingView(rootView: LaunchStatusView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
