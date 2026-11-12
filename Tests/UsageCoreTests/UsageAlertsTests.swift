import Foundation
import Testing
import UsageCore

private let start = Date(timeIntervalSince1970: 1781654300)
private let firstReset = start.addingTimeInterval(5 * 60 * 60)
private let thresholds: [Double] = [75, 90, 95]

private func display(_ percent: Double, reset: Date?, at time: Date) -> ProviderDisplay {
    var history = UsageHistory(provider: .codex)
    let window = UsageWindow(id: "primary", label: "5-hour window", usedPercent: percent, resetsAt: reset, isPrimary: true)
    history.receive(ProviderReading(provider: .codex, outcome: .sample(UsageSample(observedAt: time, windows: [window]))), at: time)
    return history.display(at: time)
}

private func kinds(
    _ tracker: inout UsageAlertTracker, _ display: ProviderDisplay, resets: Bool = true, now: Date = start
) -> [UsageAlert.Kind] {
    tracker.alerts(for: display, thresholds: thresholds, includeResets: resets, now: now).map(\.kind)
}

@Test func eachThresholdIsAnnouncedOncePerPeriodAndOnlyTheHighestOnAJump() {
    var tracker = UsageAlertTracker()
    #expect(kinds(&tracker, display(50, reset: firstReset, at: start)).isEmpty)
    #expect(kinds(&tracker, display(91, reset: firstReset, at: start)) == [.reached(90)])
    // A reset time that shifts by a few seconds is the same period.
    #expect(kinds(&tracker, display(92, reset: firstReset.addingTimeInterval(5), at: start)).isEmpty)
    #expect(kinds(&tracker, display(96, reset: firstReset, at: start)) == [.reached(95)])
}

@Test func aNewPeriodAnnouncesTheResetAndRearmsThresholds() {
    let later = firstReset.addingTimeInterval(60)
    let nextReset = firstReset.addingTimeInterval(5 * 60 * 60)

    var tracker = UsageAlertTracker()
    _ = kinds(&tracker, display(91, reset: firstReset, at: start))
    #expect(kinds(&tracker, display(3, reset: nextReset, at: later), now: later) == [.reset])
    #expect(kinds(&tracker, display(80, reset: nextReset, at: later), now: later) == [.reached(75)])

    var quiet = UsageAlertTracker()
    _ = kinds(&quiet, display(91, reset: firstReset, at: start), resets: false)
    #expect(kinds(&quiet, display(3, reset: nextReset, at: later), resets: false, now: later).isEmpty)
}

@Test func withoutResetTimesOnlyADropBelowEveryThresholdRearms() {
    var tracker = UsageAlertTracker()
    _ = kinds(&tracker, display(91, reset: nil, at: start))
    #expect(kinds(&tracker, display(80, reset: nil, at: start)).isEmpty)
    #expect(kinds(&tracker, display(10, reset: nil, at: start)) == [.reset])
}

@Test func staleAndExpiredWindowsNeverAlert() {
    let stale = start.addingTimeInterval(Provider.codex.staleAfter + 1)
    var history = UsageHistory(provider: .codex)
    let window = UsageWindow(id: "primary", label: "5-hour window", usedPercent: 99, resetsAt: stale.addingTimeInterval(60), isPrimary: true)
    history.receive(ProviderReading(provider: .codex, outcome: .sample(UsageSample(observedAt: start, windows: [window]))), at: start)
    #expect(history.display(at: stale).state == .stale)

    var tracker = UsageAlertTracker()
    #expect(kinds(&tracker, history.display(at: stale), now: stale).isEmpty)
    #expect(kinds(&tracker, display(99, reset: start.addingTimeInterval(-1), at: start)).isEmpty)
}

@Test func theTrackerSurvivesEncoding() throws {
    var tracker = UsageAlertTracker()
    _ = kinds(&tracker, display(91, reset: firstReset, at: start))
    var restored = try JSONDecoder().decode(UsageAlertTracker.self, from: JSONEncoder().encode(tracker))
    #expect(restored == tracker)
    #expect(kinds(&restored, display(91, reset: firstReset, at: start)).isEmpty)
}
