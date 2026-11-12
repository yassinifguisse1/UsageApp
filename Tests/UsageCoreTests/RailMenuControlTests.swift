#if !SWIFT_PACKAGE
import AppKit
import Testing

@MainActor
@Test func railGearOpensOncePerHoverAndLetsClicksPassThrough() async throws {
    var opens = 0
    let gear = RailMenuControl(onHover: { _ in }, onOpen: { _ in opens += 1 })
    gear.frame = NSRect(x: 0, y: 0, width: 44, height: 44)
    let entered = try #require(hoverEvent(.mouseEntered))
    let exited = try #require(hoverEvent(.mouseExited))

    #expect(gear.hitTest(NSPoint(x: 22, y: 22)) == nil)

    gear.mouseEntered(with: entered)
    gear.mouseExited(with: exited)
    try await Task.sleep(for: .milliseconds(300))
    #expect(opens == 0)

    gear.mouseEntered(with: entered)
    gear.mouseEntered(with: entered)
    try await Task.sleep(for: .milliseconds(400))
    #expect(opens == 1)
}

private func hoverEvent(_ type: NSEvent.EventType) -> NSEvent? {
    NSEvent.enterExitEvent(
        with: type, location: NSPoint(x: 22, y: 22), modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil
    )
}
#endif
