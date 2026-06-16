import AppKit
import SwiftUI

struct PointingHandCursorModifier: ViewModifier {
    var isEnabled: Bool
    @State private var isHovering = false
    @State private var didPushCursor = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                updateCursor()
            }
            .onChange(of: isEnabled) {
                updateCursor()
            }
            .onDisappear {
                popCursorIfNeeded()
                isHovering = false
            }
    }

    private func updateCursor() {
        if isHovering && isEnabled {
            pushCursorIfNeeded()
        } else {
            popCursorIfNeeded()
        }
    }

    private func pushCursorIfNeeded() {
        guard !didPushCursor else { return }
        NSCursor.pointingHand.push()
        didPushCursor = true
    }

    private func popCursorIfNeeded() {
        guard didPushCursor else { return }
        NSCursor.pop()
        didPushCursor = false
    }
}

extension View {
    func pointingHandCursor(enabled isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}
