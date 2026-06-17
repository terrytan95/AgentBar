import CoreGraphics

enum ChartTooltipPlacement {
    static let cursorOffset = CGSize(width: 16, height: 8)

    static func position(cursor: CGPoint, calloutSize: CGSize, plotSize: CGSize) -> CGPoint {
        let halfWidth = calloutSize.width / 2
        let halfHeight = calloutSize.height / 2
        let prefersRight = cursor.x + calloutSize.width + cursorOffset.width <= plotSize.width
        let prefersBelow = cursor.y + calloutSize.height + cursorOffset.height <= plotSize.height
        let proposedX = prefersRight
            ? cursor.x + halfWidth + cursorOffset.width
            : cursor.x - halfWidth - cursorOffset.width
        let proposedY = prefersBelow
            ? cursor.y + halfHeight + cursorOffset.height
            : cursor.y - halfHeight - cursorOffset.height

        return CGPoint(
            x: min(max(halfWidth, proposedX), max(halfWidth, plotSize.width - halfWidth)),
            y: min(max(halfHeight, proposedY), max(halfHeight, plotSize.height - halfHeight))
        )
    }

    static func barIndex(at x: CGFloat, plotWidth: CGFloat, barCount: Int) -> Int? {
        guard barCount > 0, plotWidth > 0, x >= 0, x < plotWidth else { return nil }
        return min(Int(x / (plotWidth / CGFloat(barCount))), barCount - 1)
    }
}
