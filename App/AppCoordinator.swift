import AppKit
import SwiftUI
import UsageCore

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = UsageModel(trendStore: UsageTrendStore())
    private let notifier = AlertNotifier()
    private lazy var updates = UpdateChecker(model: model)
    private var overlay: PanelController?
    private var statusItem: NSStatusItem?
    private lazy var settings = SettingsWindowController(
        model: model,
        chooseExecutable: { [weak self] in self?.chooseExecutable() },
        requestNotifications: { [notifier] in await notifier.requestAuthorization() }
    )
    private var settingsOpened = false
    private var timer: Timer?
    private var panelMenuExitTime: ContinuousClock.Instant?

    private struct PanelMenuHover {
        let menu: NSMenu
        let window: NSWindow
        let gearFrame: NSRect
        let fallbackFrame: NSRect
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = PanelController(model: model) { [weak self] in self?.openPanelMenu(from: $0) }
        model.onFirstLiveSetup = { [weak self] in
            guard let self, !(settingsOpened && settings.isVisible) else { return }
            let needsSetup = Provider.allCases.first { self.model.display(for: $0).setupAction != nil }
            self.openSettings(needsSetup.map(SettingsPane.init))
        }
        model.onAlerts = { [weak self] in self?.notifier.post($0) }
        model.onPanelSettingsChanged = { [weak self] in self?.overlay?.updatePlacement() }
        installMenu()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWoke),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if !model.isDemo { model.refresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        model.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "UsageApp")
            ?? NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "UsageApp")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "UsageApp"
        item.button?.setAccessibilityLabel("UsageApp")
        item.menu = makeUsageMenu()
        statusItem = item
    }

    private func makeUsageMenu() -> NSMenu {
        let menu = NSMenu(title: "UsageApp")
        menu.delegate = self
        menuNeedsUpdate(menu)
        return menu
    }

    private func openPanelMenu(from anchor: NSView) {
        guard let window = anchor.window else { return }
        let menu = makeUsageMenu()
        let gearFrame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = menu.size
        let rightEdge = window.frame.minX - 6
        let menuFrame = NSRect(
            x: rightEdge - size.width, y: gearFrame.midY - size.height / 2,
            width: size.width, height: size.height
        )
        let x = NSApp.userInterfaceLayoutDirection == .rightToLeft ? menuFrame.maxX : menuFrame.minX
        let hover = PanelMenuHover(menu: menu, window: window, gearFrame: gearFrame, fallbackFrame: menuFrame)
        let hoverTimer = Timer(
            timeInterval: 0.05, target: self, selector: #selector(updatePanelMenuHover(_:)),
            userInfo: hover, repeats: true
        )
        RunLoop.main.add(hoverTimer, forMode: .eventTracking)
        defer {
            hoverTimer.invalidate()
            panelMenuExitTime = nil
        }
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: menuFrame.maxY), in: nil)
    }

    @objc private func updatePanelMenuHover(_ timer: Timer) {
        guard let hover = timer.userInfo as? PanelMenuHover else { return }
        let menu = hover.menu
        guard hover.window.isVisible else {
            timer.invalidate()
            menu.cancelTracking()
            return
        }
        let pointer = NSEvent.mouseLocation
        let visibleFrame = menu.accessibilityFrame()
        let menuFrame = visibleFrame.isEmpty ? hover.fallbackFrame : visibleFrame
        let gearFrame = hover.gearFrame
        let crossingGap = pointer.x >= menuFrame.maxX && pointer.x <= gearFrame.minX
            && pointer.y >= gearFrame.minY && pointer.y <= gearFrame.maxY
        if gearFrame.contains(pointer) || crossingGap || menuFrame.contains(pointer)
            || containsPointerInSubmenu(pointer, of: menu) {
            panelMenuExitTime = nil
        } else if let panelMenuExitTime {
            if panelMenuExitTime.duration(to: .now) >= .milliseconds(250) {
                timer.invalidate()
                menu.cancelTracking()
            }
        } else {
            panelMenuExitTime = .now
        }
    }

    private func containsPointerInSubmenu(_ pointer: NSPoint, of menu: NSMenu) -> Bool {
        menu.items.contains { item in
            guard let submenu = item.submenu else { return false }
            let frame = submenu.accessibilityFrame()
            return !frame.isEmpty && (frame.contains(pointer) || containsPointerInSubmenu(pointer, of: submenu))
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let update = model.availableUpdate {
            let download = item("Update Available: UsageApp \(update.version.description)…", action: #selector(openUpdate))
            download.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(download)
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: model.isDemo ? "Usage (Demo)" : "Usage"))
        for provider in model.visibleProviders {
            menu.addItem(usageItem(for: provider))
        }
        menu.addItem(.separator())
        menu.addItem(item(overlay?.isShown == true ? "Hide Panel" : "Show Panel", action: #selector(togglePanel)))
        menu.addItem(item("Refresh Now", action: #selector(refresh), key: "r"))
        menu.addItem(item(model.isDemo ? "Switch to Live Usage" : "Switch to Demo Mode", action: #selector(toggleMode)))

        let displays = NSMenu(title: "Display")
        let primary = item("Primary Display (Automatic)", action: #selector(selectDisplay(_:)))
        primary.state = overlay?.selectedDisplayID == nil ? .on : .off
        displays.addItem(primary)
        displays.addItem(.separator())
        for screen in NSScreen.screens {
            guard let identifier = PanelController.identifier(for: screen) else { continue }
            let display = item(screen.localizedName, action: #selector(selectDisplay(_:)))
            display.representedObject = identifier
            display.state = overlay?.selectedDisplayID == identifier ? .on : .off
            displays.addItem(display)
        }
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.submenu = displays
        menu.addItem(displayItem)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(openSettingsFromMenu), key: ","))
        menu.addItem(item("Quit UsageApp", action: #selector(quit), key: "q"))
    }

    /// A glanceable reading for when the panel is tucked away. Choosing it opens that provider's settings.
    private func usageItem(for provider: Provider) -> NSMenuItem {
        let reading = model.display(for: provider)
        let usage = item(provider.name, action: #selector(openProviderSettings(_:)))
        usage.representedObject = provider.rawValue
        usage.image = provider.logoImage(size: 16)
        usage.badge = NSMenuItemBadge(string: reading.headline?.percent.map(UsageFormat.percent) ?? reading.state.shortLabel)
        if #available(macOS 14.4, *), let headline = reading.headline {
            usage.subtitle = headline.resetsAt.map { "\(headline.label) · resets \(UsageFormat.date($0))" } ?? headline.label
        }
        return usage
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func tick() {
        model.tick(visible: overlay?.visible == true || settingsOpened && settings.isVisible)
        overlay?.updateCard()
        updates.checkIfDue()
    }

    @objc private func openUpdate() {
        if let url = model.availableUpdate?.url { NSWorkspace.shared.open(url) }
    }

    @objc private func togglePanel() {
        overlay?.toggle()
        tick()
    }

    @objc private func refresh() {
        model.refresh()
        overlay?.updateCard()
    }

    @objc private func toggleMode() {
        model.setDemo(!model.isDemo)
        overlay?.updateCard()
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        overlay?.chooseDisplay(sender.representedObject as? String)
    }

    @objc private func screenChanged() {
        overlay?.updatePlacement()
    }

    @objc private func systemWoke() {
        tick()
        if !model.isDemo { refresh() }
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func openProviderSettings(_ sender: NSMenuItem) {
        guard let provider = (sender.representedObject as? String).flatMap(Provider.init(rawValue:)) else { return }
        openSettings(SettingsPane(provider))
    }

    private func openSettings(_ pane: SettingsPane? = nil) {
        settingsOpened = true
        settings.show(pane)
        tick()
    }

    private func chooseExecutable() {
        guard let window = settings.window else { return }
        let picker = NSOpenPanel()
        picker.message = "Select the Codex CLI executable."
        picker.prompt = "Choose Executable"
        picker.canChooseDirectories = false
        picker.resolvesAliases = true
        picker.showsHiddenFiles = true
        picker.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            self?.model.setCodexExecutable(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
