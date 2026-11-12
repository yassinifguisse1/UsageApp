import AppKit

final class RailMenuControl: NSButton {
    var onOpen: (NSView) -> Void

    init(onOpen: @escaping (NSView) -> Void) {
        self.onOpen = onOpen
        super.init(frame: .zero)
        cell = MenuButtonCell()
        isBordered = false
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        toolTip = "Show UsageApp Menu"
        setAccessibilityLabel("UsageApp Menu")
        target = self
        action = #selector(openMenu)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHiddenOrHasHiddenAncestor, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    @objc private func openMenu() {
        // Finish the button action before AppKit begins tracking the menu.
        Task { @MainActor [weak self] in
            guard let self else { return }
            onOpen(self)
        }
    }
}

private final class MenuButtonCell: NSButtonCell {
    override func hitTest(for event: NSEvent, in cellFrame: NSRect, of controlView: NSView) -> NSCell.HitResult {
        let point = controlView.convert(event.locationInWindow, from: nil)
        // The gear's padding is part of the click target.
        return controlView.isMousePoint(point, in: cellFrame) ? [.contentArea, .trackableArea] : []
    }
}
