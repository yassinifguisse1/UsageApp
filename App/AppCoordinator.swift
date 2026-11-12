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
    private var setupWindow: NSWindow?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = PanelController(model: model) { [weak self] in self?.openPanelMenu(from: $0) }
        model.onFirstLiveSetup = { [weak self] in
            guard let self, self.setupWindow?.isVisible != true else { return }
            self.openSetup()
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
        let center = window.convertPoint(toScreen: anchor.convert(
            NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil
        ))
        let rightEdge = window.frame.minX - 6
        let x = NSApp.userInterfaceLayoutDirection == .rightToLeft ? rightEdge : rightEdge - menu.size.width
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: center.y + menu.size.height / 2), in: nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let update = model.availableUpdate {
            let download = item("Update Available: UsageApp \(update.version.description)…", action: #selector(openUpdate))
            download.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(download)
            menu.addItem(.separator())
        }
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
        menu.addItem(item("Settings & Usage…", action: #selector(openSetup), key: ","))
        menu.addItem(item("Quit UsageApp", action: #selector(quit), key: "q"))
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func tick() {
        model.tick(visible: overlay?.visible == true || setupWindow?.isVisible == true)
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

    @objc private func openSetup() {
        let window = setupWindow ?? makeSetupWindow()
        setupWindow = window
        NSApp.activate()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        tick()
    }

    private func makeSetupWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 690),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings & Usage"
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentMinSize = NSSize(width: 360, height: 300)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(
            model: model,
            chooseExecutable: { [weak self] in self?.chooseExecutable() },
            requestNotifications: { [notifier] in await notifier.requestAuthorization() }
        ))
        window.center()
        return window
    }

    private func chooseExecutable() {
        guard let setupWindow else { return }
        let picker = NSOpenPanel()
        picker.message = "Select the Codex CLI executable."
        picker.prompt = "Choose Executable"
        picker.canChooseDirectories = false
        picker.resolvesAliases = true
        picker.showsHiddenFiles = true
        picker.beginSheetModal(for: setupWindow) { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            self?.model.setCodexExecutable(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
