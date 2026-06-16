import CoreGraphics

enum PopoverLayout {
    static let horizontalInset: CGFloat = 14
    static let width: CGFloat = 380
    static let minimumHeight: CGFloat = 420
    static let defaultHeight: CGFloat = 720
    static let maximumHeight: CGFloat = 860
    static let screenFrameClearance: CGFloat = 48

    private static let baseHeight: CGFloat = 280
    private static let accountRowHeight: CGFloat = 72
    private static let sourceRowHeight: CGFloat = 22

    static func maximumHeight(forScreenHeight screenHeight: CGFloat?) -> CGFloat {
        guard let screenHeight else { return maximumHeight }
        return max(minimumHeight, screenHeight - screenFrameClearance)
    }

    static func height(
        accountCount: Int,
        sourceCount: Int,
        preferredHeight: CGFloat? = nil,
        maximumHeight: CGFloat = maximumHeight
    ) -> CGFloat {
        if let preferredHeight {
            return min(maximumHeight, max(minimumHeight, preferredHeight))
        }
        let contentHeight = baseHeight
            + CGFloat(max(0, accountCount)) * accountRowHeight
            + CGFloat(max(0, sourceCount)) * sourceRowHeight
        return min(defaultHeight, max(minimumHeight, contentHeight))
    }
}
