import AppKit

final class RailMenuControl: NSView {
    var onHover: (Bool) -> Void
    var onOpen: (NSView) -> Void
    private var isHovered = false
    private var pendingOpen: Task<Void, Never>?

    init(onHover: @escaping (Bool) -> Void, onOpen: @escaping (NSView) -> Void) {
        self.onHover = onHover
        self.onOpen = onOpen
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ inside: Bool) {
        guard isHovered != inside else { return }
        isHovered = inside
        onHover(inside)
        pendingOpen?.cancel()
        pendingOpen = nil
        guard inside else { return }

        pendingOpen = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            pendingOpen = nil
            onOpen(self)

            // Menu tracking can consume the exit event when the pointer moves into the menu.
            if let window, !bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
                setHovered(false)
            }
        }
    }
}
