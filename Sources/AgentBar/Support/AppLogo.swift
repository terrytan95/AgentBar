import AppKit

enum AppLogo {
    static func image() -> NSImage {
        if let image = NSImage(named: "AgentBarLogo") {
            return image
        }
        if let url = Bundle.main.url(forResource: "AgentBarLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "AgentBar") ?? NSImage()
    }

    static func menuBarImage() -> NSImage {
        if let image = NSImage(named: "AgentBarMenuIcon") {
            return image
        }
        if let url = Bundle.main.url(forResource: "AgentBarMenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return image()
    }

    static func templateImage() -> NSImage {
        let image = menuBarImage().copy() as? NSImage ?? menuBarImage()
        image.isTemplate = false
        return image
    }
}
