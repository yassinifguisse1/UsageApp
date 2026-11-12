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
    private var preferredDisplay: String?
    private var hovered: Provider?
    private var pointerInCard = false
    private var dismissal: Task<Void, Never>?
    private var renderedReading: ProviderDisplay?
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
            onHover: { [weak self] provider, inside in self?.hover(provider, inside: inside) },
            onClick: { [weak self] provider in self?.toggleDetails(provider) },
            onOpenMenu: { [weak self] anchor in
                if self?.model.pinnedProvider == nil { self?.closeCard() }
                onOpenMenu(anchor)
            }
        ))
        updatePlacement()
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
            hovered = nil
            closeCard()
            return
        }
        let area = screen.visibleFrame
        let railTop = (area.midY + UsageRail.providerHeight / 2).rounded()
        let frame = NSRect(
            x: area.maxX - UsageRail.width,
            y: max(area.minY, railTop - UsageRail.height),
            width: UsageRail.width, height: UsageRail.height
        )
        rail.setFrame(frame, display: true)
        rail.orderFrontRegardless()
        updateCard()
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
        let details = UsageDetails(reading: reading, isDemo: model.isDemo, isHUD: true, isPinned: isPinned) { [weak self] in
            self?.togglePin(activeCard)
        }
        let contentChanged = reading != renderedReading || model.isDemo != renderedDemo
            || renderedWidth != width || renderedHeightLimit != heightLimit
        if contentChanged {
            let measure = NSHostingView(rootView: details
                .padding(17)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true))
            renderedHeight = min(heightLimit, max(106, ceil(measure.fittingSize.height)))
            renderedReading = reading
            renderedDemo = model.isDemo
            renderedWidth = width
            renderedHeightLimit = heightLimit
        }

        let center = rail.frame.maxY - UsageRail.ringCenter(for: activeCard)
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
