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
        if let url = Bundle.module.url(forResource: "AgentBarLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "AgentBar") ?? NSImage()
    }

    static func templateImage() -> NSImage {
        let image = image().copy() as? NSImage ?? image()
        image.isTemplate = false
        return image
    }
}
