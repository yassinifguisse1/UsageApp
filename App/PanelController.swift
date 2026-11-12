import AppKit
import CoreGraphics
import SwiftUI
import UsageCore

@MainActor
final class PanelController {
    private let model: UsageModel
    private let defaults: UserDefaults
    private let rail = OverlayPanel()
    private let card = OverlayPanel()
    private let edgeTab = OverlayPanel()
    private let presentation = RailPresentation()
    private var pointerMonitors: [Any] = []
    private var revealing: Task<Void, Never>?
    private var concealing: Task<Void, Never>?
    private var menuOpen = false
    private var preferredDisplay: String?
    private var hovered: Provider?
    private var pointerInCard = false
    private var dismissal: Task<Void, Never>?
    private var renderedReading: ProviderDisplay?
    private var renderedTrend: [UsagePoint] = []
    private var renderedDemo = false
    private var renderedWidth: CGFloat = 0
    private var renderedHeightLimit: CGFloat = 0
    private var renderedHeight: CGFloat = 0
    private var renderedTip: CGFloat = 0
    private var renderedPinned = false

    private(set) var isShown: Bool

    init(model: UsageModel, defaults: UserDefaults = .standard, onOpenMenu: @escaping (NSView) -> Void) {
        self.model = model
        self.defaults = defaults
        preferredDisplay = defaults.string(forKey: "preferredDisplay")
        isShown = defaults.object(forKey: "panelShown") as? Bool ?? true
        rail.title = "Usage Panel"
        card.title = "Usage Details"
        rail.contentView = OverlayHostingView(rootView: UsageRail(
            model: model,
            presentation: presentation,
            onHover: { [weak self] provider, inside in self?.hover(provider, inside: inside) },
            onClick: { [weak self] provider in self?.toggleDetails(provider) },
            onOpenMenu: { [weak self] anchor in
                guard let self, isShown, presentation.isRevealed, !menuOpen, rail.isVisible,
                      NSEvent.pressedMouseButtons == 0,
                      anchor.bounds.contains(anchor.convert(rail.mouseLocationOutsideOfEventStream, from: nil))
                else { return }
                if model.pinnedProvider == nil { closeCard() }
                // The menu tracks synchronously. Keep the rail out until it closes.
                concealing?.cancel()
                concealing = nil
                menuOpen = true
                onOpenMenu(anchor)
                menuOpen = false
                pointerMoved()
            }
        ))
        edgeTab.title = "Usage Panel Tab"
        edgeTab.hasShadow = false
        edgeTab.ignoresMouseEvents = true
        edgeTab.contentView = OverlayHostingView(rootView: EdgeTab(model: model))
        presentation.isRevealed = !revealsOnHover
        watchPointer()
        updatePlacement()
    }

    /// VoiceOver can't point at the edge, so the panel stays out while it runs.
    private var revealsOnHover: Bool {
        model.revealsPanelOnHover && !NSWorkspace.shared.isVoiceOverEnabled
    }

    var selectedDisplayID: String? { preferredDisplay }
    var visible: Bool { rail.isVisible }

    func toggle() {
        isShown.toggle()
        defaults.set(isShown, forKey: "panelShown")
        updatePlacement()
    }

    func chooseDisplay(_ id: String?) {
        preferredDisplay = id
        defaults.set(id, forKey: "preferredDisplay")
        hovered = nil
        closeCard()
        updatePlacement()
    }

    func updatePlacement() {
        guard isShown, let screen = targetDisplay else {
            rail.orderOut(nil)
            edgeTab.orderOut(nil)
            hovered = nil
            closeCard()
            return
        }
        let area = screen.visibleFrame
        let providers = model.visibleProviders
        if let shown = model.detailsProvider, !providers.contains(shown) { closeCard() }
        let railTop = (area.midY + UsageRail.providerHeight(for: providers) / 2).rounded()
        let height = UsageRail.height(for: providers)
        let frame = NSRect(
            x: area.maxX - UsageRail.width,
            y: max(area.minY, railTop - height),
            width: UsageRail.width, height: height
        )
        rail.setFrame(frame, display: true)
        let tab = EdgeTab.size
        edgeTab.setFrame(
            NSRect(x: area.maxX - tab.width, y: (area.midY - tab.height / 2).rounded(), width: tab.width, height: tab.height),
            display: true
        )

        if revealsOnHover {
            if presentation.isRevealed {
                rail.orderFrontRegardless()
                edgeTab.orderOut(nil)
            } else {
                rail.orderOut(nil)
                edgeTab.alphaValue = 1
                edgeTab.orderFrontRegardless()
            }
            pointerMoved()
        } else {
            revealing?.cancel()
            concealing?.cancel()
            revealing = nil
            concealing = nil
            presentation.isRevealed = true
            edgeTab.orderOut(nil)
            rail.orderFrontRegardless()
        }
        updateCard()
    }

    // MARK: Reveal on hover

    private func watchPointer() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        // Pointer movement needs no special permission. Only keyboard monitoring does.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { pointerMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { pointerMonitors.append(local) }
    }

    private func pointerMoved() {
        guard isShown, revealsOnHover, !menuOpen else { return }
        let pointer = NSEvent.mouseLocation
        if presentation.isRevealed {
            if keepsRailOut(pointer) {
                concealing?.cancel()
                concealing = nil
            } else if concealing == nil {
                concealing = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(420))
                    guard !Task.isCancelled else { return }
                    self?.conceal()
                }
            }
        } else if isAtEdge(pointer) {
            guard revealing == nil else { return }
            // A short dwell, so passing through to another display doesn't open the panel.
            revealing = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let self else { return }
                revealing = nil
                if isAtEdge(NSEvent.mouseLocation) { reveal() }
            }
        } else {
            revealing?.cancel()
            revealing = nil
        }
    }

    private func isAtEdge(_ pointer: NSPoint) -> Bool {
        guard let area = targetDisplay?.visibleFrame else { return false }
        let band = rail.frame.insetBy(dx: 0, dy: -12)
        return pointer.x >= area.maxX - 4 && pointer.x <= area.maxX + 1
            && pointer.y >= band.minY && pointer.y <= band.maxY
    }

    private func keepsRailOut(_ pointer: NSPoint) -> Bool {
        model.pinnedProvider != nil || menuOpen
            || rail.frame.insetBy(dx: -14, dy: -18).contains(pointer)
            || card.isVisible && card.frame.insetBy(dx: -14, dy: -14).contains(pointer)
    }

    private func reveal() {
        guard isShown, revealsOnHover, !presentation.isRevealed else { return }
        concealing?.cancel()
        concealing = nil
        rail.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            edgeTab.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presentation.isRevealed else { return }
                self.edgeTab.orderOut(nil)
            }
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.82)) {
            presentation.isRevealed = true
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.rail.invalidateShadow()
            try? await Task.sleep(for: .milliseconds(700))
            self?.presentation.sweepsArcs = false
        }
    }

    private func conceal() {
        concealing = nil
        guard revealsOnHover, presentation.isRevealed, !keepsRailOut(NSEvent.mouseLocation) else { return }
        hovered = nil
        closeCard()
        withAnimation(.easeIn(duration: 0.2)) {
            presentation.isRevealed = false
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(230))
            guard let self, !presentation.isRevealed, isShown else { return }
            rail.orderOut(nil)
            edgeTab.alphaValue = 0
            edgeTab.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.edgeTab.animator().alphaValue = 1
            }, completionHandler: nil)
        }
    }

    func updateCard() {
        guard let activeCard = model.detailsProvider, let screen = targetDisplay, rail.isVisible else { return }
        let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let gap: CGFloat = 5
        let width = min(316, rail.frame.minX - available.minX - gap - UsageCallout.tipWidth)
        let heightLimit = min(480, available.height)
        guard width >= 172, heightLimit >= 100 else {
            closeCard()
            return
        }

        let reading = model.display(for: activeCard)
        let isPinned = model.pinnedProvider == activeCard
        let trend = model.trend(for: activeCard)
        let details = UsageDetails(
            reading: reading, isDemo: model.isDemo, isHUD: true, isPinned: isPinned, trend: trend
        ) { [weak self] in
            self?.togglePin(activeCard)
        }
        let contentChanged = reading != renderedReading || trend != renderedTrend || model.isDemo != renderedDemo
            || renderedWidth != width || renderedHeightLimit != heightLimit
        if contentChanged {
            let measure = NSHostingView(rootView: details
                .padding(17)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true))
            renderedHeight = min(heightLimit, max(106, ceil(measure.fittingSize.height)))
            renderedReading = reading
            renderedTrend = trend
            renderedDemo = model.isDemo
            renderedWidth = width
            renderedHeightLimit = heightLimit
        }

        let center = rail.frame.maxY - UsageRail.ringCenter(for: activeCard, in: model.visibleProviders)
        let y = max(available.minY, min(center - renderedHeight / 2, available.maxY - renderedHeight)).rounded()
        let tipY = y + renderedHeight - center
        if contentChanged || renderedTip != tipY || renderedPinned != isPinned {
            let callout = UsageCallout(
                details: details,
                width: width, height: renderedHeight, tipY: tipY,
                onHover: { [weak self] inside in self?.hoverCard(inside) }
            )
            if let hosting = card.contentView as? OverlayHostingView<UsageCallout> {
                hosting.rootView = callout
            } else {
                card.contentView = OverlayHostingView(rootView: callout)
            }
            renderedTip = tipY
            renderedPinned = isPinned
        }

        let totalWidth = width + UsageCallout.tipWidth
        let frame = NSRect(x: rail.frame.minX - totalWidth - gap, y: y, width: totalWidth, height: renderedHeight)
        if card.frame != frame {
            card.setFrame(frame, display: true)
            card.invalidateShadow()
        }
        if !card.isVisible {
            showCard()
        }
    }

    private func showCard() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            card.alphaValue = 1
            card.orderFrontRegardless()
            return
        }
        card.alphaValue = 0
        card.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            card.animator().alphaValue = 1
        }
    }

    private var targetDisplay: NSScreen? {
        NSScreen.screens.first { screen in
            guard let preferredDisplay else { return false }
            return Self.identifier(for: screen) == preferredDisplay
        } ?? NSScreen.screens.first
    }

    static func identifier(for screen: NSScreen) -> String? {
        guard let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(value.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func hover(_ provider: Provider, inside: Bool) {
        if inside {
            guard hovered != provider else { return }
            hovered = provider
            dismissal?.cancel()
            guard model.pinnedProvider == nil else { return }
            model.detailsProvider = provider
            updateCard()
        } else if hovered == provider {
            hovered = nil
            dismissPreviewSoon()
        }
    }

    private func hoverCard(_ inside: Bool) {
        pointerInCard = inside
        if inside { dismissal?.cancel() }
        else { dismissPreviewSoon() }
    }

    private func toggleDetails(_ provider: Provider) {
        if model.detailsProvider == provider {
            closeCard()
            return
        }

        dismissal?.cancel()
        model.setPinnedProvider(nil)
        model.detailsProvider = provider
        updateCard()
    }

    private func togglePin(_ provider: Provider) {
        guard model.detailsProvider == provider else { return }
        if model.pinnedProvider == provider {
            closeCard()
        } else {
            dismissal?.cancel()
            model.setPinnedProvider(provider)
            updateCard()
        }
    }

    private func dismissPreviewSoon() {
        guard model.pinnedProvider == nil else { return }
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let self, self.hovered == nil, !self.pointerInCard else { return }
            self.closeCard()
        }
    }

    private func closeCard() {
        dismissal?.cancel()
        model.detailsProvider = nil
        model.setPinnedProvider(nil)
        pointerInCard = false
        card.orderOut(nil)
    }
}
