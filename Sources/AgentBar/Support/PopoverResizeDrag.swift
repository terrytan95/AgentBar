import Foundation

struct PopoverResizeDrag: Equatable, Sendable {
    static let minimumIntermediateDelta = 2.0

    var bounds: PanelResizeBounds

    func height(startHeight: Double, startScreenY: Double, currentScreenY: Double) -> Double {
        bounds.height(
            startHeight: startHeight,
            translation: startScreenY - currentScreenY
        )
    }

    static func shouldEmit(
        previousHeight: Double?,
        nextHeight: Double,
        isFinal: Bool,
        minimumDelta: Double = minimumIntermediateDelta
    ) -> Bool {
        guard !isFinal, let previousHeight else { return true }
        return abs(previousHeight - nextHeight) >= minimumDelta
    }
}
