import AppKit
import UsageCore

enum SettingsPane: String, CaseIterable {
    case general, notifications, claude, codex, perplexity

    init(_ provider: Provider) {
        self = switch provider {
        case .claude: .claude
        case .codex: .codex
        case .perplexity: .perplexity
        }
    }

    var provider: Provider? {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .perplexity: .perplexity
        case .general, .notifications: nil
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .notifications: "Notifications"
        case .claude, .codex, .perplexity: provider?.name ?? ""
        }
    }

    var image: NSImage? {
        switch self {
        case .general: NSImage(systemSymbolName: "gearshape", accessibilityDescription: title)
        case .notifications: NSImage(systemSymbolName: "bell.badge", accessibilityDescription: title)
        case .claude, .codex, .perplexity: provider?.logoImage(size: 24)
        }
    }
}
