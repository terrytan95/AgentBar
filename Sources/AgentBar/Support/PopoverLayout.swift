import CoreGraphics

enum PopoverLayout {
    static let width: CGFloat = 380
    static let minimumHeight: CGFloat = 420
    static let defaultHeight: CGFloat = 720
    static let maximumHeight: CGFloat = 860

    private static let baseHeight: CGFloat = 280
    private static let accountRowHeight: CGFloat = 84
    private static let sourceRowHeight: CGFloat = 22

    static func height(accountCount: Int, sourceCount: Int, preferredHeight: CGFloat? = nil) -> CGFloat {
        if let preferredHeight {
            return min(maximumHeight, max(minimumHeight, preferredHeight))
        }
        let contentHeight = baseHeight
            + CGFloat(max(0, accountCount)) * accountRowHeight
            + CGFloat(max(0, sourceCount)) * sourceRowHeight
        return min(defaultHeight, max(minimumHeight, contentHeight))
    }
}
