#if !SWIFT_PACKAGE
import AppKit
import Testing

@MainActor
@Test func railGearTracksClicksInItsPadding() throws {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 80))
    let button = RailMenuControl(onOpen: { _ in })
    button.frame = NSRect(x: 16, y: 18, width: 44, height: 44)
    container.addSubview(button)
    let cell = try #require(button.cell)

    for point in [NSPoint(x: 17, y: 19), NSPoint(x: 38, y: 40), NSPoint(x: 59, y: 61)] {
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        #expect(container.hitTest(point) === button)
        #expect(button.acceptsFirstMouse(for: event))
        #expect(cell.hitTest(for: event, in: button.bounds, of: button).contains(.trackableArea))
    }

    #expect(container.hitTest(NSPoint(x: 15, y: 40)) !== button)
}
#endif
