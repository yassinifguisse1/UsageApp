import AppKit
import SwiftUI
import UsageCore

/// A standard macOS settings window: toolbar panes, a pane title, and no minimize or resize.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let tabs = SettingsTabsController()
    private let defaults: UserDefaults

    init(
        model: UsageModel,
        defaults: UserDefaults = .standard,
        chooseExecutable: @escaping () -> Void,
        requestNotifications: @escaping () async -> Bool
    ) {
        self.defaults = defaults
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for pane in SettingsPane.allCases {
            let item = switch pane {
            case .general:
                Self.item(for: pane, GeneralSettingsPane(model: model))
            case .notifications:
                Self.item(for: pane, NotificationSettingsPane(model: model, requestNotifications: requestNotifications))
            case .claude, .codex, .perplexity:
                Self.item(for: pane, ProviderSettingsPane(
                    model: model, provider: pane.provider ?? .claude, chooseExecutable: chooseExecutable
                ))
            }
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let saved = defaults.string(forKey: "settingsPane").flatMap(SettingsPane.init(rawValue:))
        select(saved ?? .general)
        tabs.onSelect = { [weak defaults] pane in defaults?.set(pane.rawValue, forKey: "settingsPane") }
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    var isVisible: Bool { window?.isVisible == true }

    /// Opens the window on the given pane, or on the pane used last.
    func show(_ pane: SettingsPane? = nil) {
        if let pane { select(pane) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private static func item<Content: View>(for pane: SettingsPane, _ content: Content) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        hosting.title = pane.title
        let item = NSTabViewItem(viewController: hosting)
        item.identifier = pane.rawValue
        item.label = pane.title
        item.image = pane.image
        return item
    }

    private func select(_ pane: SettingsPane) {
        if let index = SettingsPane.allCases.firstIndex(of: pane) {
            tabs.selectedTabViewItemIndex = index
        }
    }
}

private final class SettingsTabsController: NSTabViewController {
    var onSelect: ((SettingsPane) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String, let pane = SettingsPane(rawValue: id) {
            onSelect?(pane)
        }
    }
}
