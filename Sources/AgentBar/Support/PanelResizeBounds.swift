import Foundation

struct PanelResizeBounds: Equatable, Sendable {
    var minHeight: Double
    var maxHeight: Double

    func height(startHeight: Double, translation: Double) -> Double {
        min(max(startHeight + translation, minHeight), maxHeight)
    }
}
