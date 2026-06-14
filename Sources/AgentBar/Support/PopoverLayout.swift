import CoreGraphics

enum PopoverLayout {
    static let width: CGFloat = 430
    static let minimumHeight: CGFloat = 460
    static let maximumHeight: CGFloat = 860

    private static let baseHeight: CGFloat = 312
    private static let accountRowHeight: CGFloat = 92
    private static let sourceRowHeight: CGFloat = 24

    static func height(accountCount: Int, sourceCount: Int) -> CGFloat {
        let contentHeight = baseHeight
            + CGFloat(max(0, accountCount)) * accountRowHeight
            + CGFloat(max(0, sourceCount)) * sourceRowHeight
        return min(maximumHeight, max(minimumHeight, contentHeight))
    }
}
