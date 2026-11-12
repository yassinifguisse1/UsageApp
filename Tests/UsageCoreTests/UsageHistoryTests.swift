import Foundation
import Testing
import UsageCore

private let start = Date(timeIntervalSince1970: 1781654300)
private let deadline = start.addingTimeInterval(10)
private let weekly = UsageWindow(id: "weekly", label: "7-day window", usedPercent: 14, resetsAt: nil)

private func primary(percent: Double, reset: Date?) -> UsageWindow {
    UsageWindow(id: "primary", label: "5-hour window", usedPercent: percent, resetsAt: reset, isPrimary: true)
}

private func sample(_ time: Date, _ windows: [UsageWindow]) -> ProviderReading {
    ProviderReading(provider: .codex, outcome: .sample(UsageSample(observedAt: time, windows: windows)))
}

@Test func resetWithholdsOnlyThatPercentageUntilFreshFutureResetArrives() throws {
    var history = UsageHistory(provider: .codex)
    history.receive(sample(start, [primary(percent: 87, reset: deadline), weekly]), at: start)
    #expect(history.display(at: start).headline?.percent == 87)
    #expect(history.display(at: deadline).headline?.percent == nil)
    #expect(history.display(at: deadline).state == .awaitingReset)

    let later = deadline.addingTimeInterval(1)
    history.receive(sample(later, [weekly]), at: later)
    var display = history.display(at: later)
    #expect(display.headline?.id == "primary")
    #expect(display.headline?.percent == nil)
    #expect(display.windows.first { $0.id == "weekly" }?.percent == 14)

    history.receive(sample(later, [primary(percent: 0, reset: nil), weekly]), at: later)
    #expect(history.display(at: later).headline?.percent == nil)

    history.receive(sample(later, [primary(percent: 0, reset: deadline), weekly]), at: later)
    #expect(history.display(at: later).headline?.percent == nil)

    history.receive(sample(later, [primary(percent: 0, reset: later.addingTimeInterval(300)), weekly]), at: later)
    display = history.display(at: later)
    #expect(display.state == .current)
    #expect(display.headline?.percent == 0)
    #expect(display.observedAt == later)
}

@Test func missingReadingUsesAStateOrLabeledFallbackAndNeverAnInventedZero() {
    var history = UsageHistory(provider: .codex)
    #expect(history.display(at: start).state == .unavailable)
    #expect(history.display(at: start).headline == nil)

    history.receive(sample(start, [weekly]), at: start)
    #expect(history.display(at: start).headline?.label == "7-day window")
    #expect(history.display(at: start).headline?.percent == 14)
    #expect(history.display(at: start.addingTimeInterval(300)).state == .stale)

    history.receive(ProviderReading(provider: .codex, outcome: .unavailable("Timed out")), at: start)
    #expect(history.display(at: start).state == .stale)
    #expect(history.display(at: start).observedAt == start)

    history.receive(ProviderReading(provider: .codex, outcome: .setupRequired("Sign in")), at: start)
    #expect(history.display(at: start).state == .setupRequired)
    #expect(history.display(at: start).headline == nil)
    #expect(history.display(at: start).observedAt == nil)
}
