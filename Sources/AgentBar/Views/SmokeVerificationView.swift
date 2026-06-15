import AppKit
import SwiftUI

struct SmokeVerificationView: View {
    @StateObject private var store = UsageStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(nsImage: AppLogo.image())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text("AgentBar smoke verification")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Menu bar: \(store.menuBarTitle)")
                    .font(.headline.monospacedDigit())
            }
            HStack(alignment: .top, spacing: 12) {
                PopoverRootView(store: store)
                    .frame(width: 420, height: 560)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(spacing: 12) {
                    SettingsView(store: store)
                        .frame(width: 540, height: 470)
                }
            }
            StatisticsView(store: store, initialTab: .settings)
                .frame(height: 390)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(width: 1010, height: 1180)
        .background(.regularMaterial)
    }
}

@MainActor
final class SmokeVerificationWindowController {
    static let shared = SmokeVerificationWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 60, width: 1010, height: 1180),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentBar Smoke Verification"
        window.contentView = NSHostingView(rootView: SmokeVerificationView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
