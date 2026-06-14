import CoreGraphics

enum PopoverLayout {
    static let width: CGFloat = 380
    static let minimumHeight: CGFloat = 420
    static let maximumHeight: CGFloat = 720

    private static let baseHeight: CGFloat = 280
    private static let accountRowHeight: CGFloat = 84
    private static let sourceRowHeight: CGFloat = 22

    static func height(accountCount: Int, sourceCount: Int) -> CGFloat {
        let contentHeight = baseHeight
            + CGFloat(max(0, accountCount)) * accountRowHeight
            + CGFloat(max(0, sourceCount)) * sourceRowHeight
        return min(maximumHeight, max(minimumHeight, contentHeight))
    }
}
