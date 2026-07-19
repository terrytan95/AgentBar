import AppKit

enum AppLogo {
    static func image() -> NSImage {
        if let url = Bundle.main.url(forResource: "AgentBarLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "AgentBar") ?? NSImage()
    }

    static func menuBarImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "AgentBarMenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return image()
    }
}
