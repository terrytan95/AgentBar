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

enum ProviderIcon {
    static func image(for service: UsageService) -> NSImage {
        let resourceName = switch service {
        case .codex: "codex"
        case .claudeCode: "claude-code"
        case .xaiAPI: "grok"
        case .cursorAgent: "cursor-agent"
        case .antigravity: "antigravity"
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "svg", subdirectory: "ProviderIcons")
            ?? Bundle.module.url(forResource: resourceName, withExtension: "svg", subdirectory: "ProviderIcons"),
            let image = NSImage(contentsOf: url)
        else {
            let symbol = service == .antigravity ? "sparkles" : "terminal"
            return NSImage(systemSymbolName: symbol, accessibilityDescription: service.rawValue) ?? NSImage()
        }
        image.isTemplate = true
        return image
    }
}
