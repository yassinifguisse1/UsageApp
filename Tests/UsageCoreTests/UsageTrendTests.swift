import Foundation
import Testing
import UsageCore

private let start = Date(timeIntervalSince1970: 1781654300)
private let reset = start.addingTimeInterval(5 * 60 * 60)

private func display(_ percent: Double, reset: Date?, at time: Date, id: String = "primary") -> ProviderDisplay {
    var history = UsageHistory(provider: .claude)
    let window = UsageWindow(id: id, label: "5-hour window", usedPercent: percent, resetsAt: reset, isPrimary: true)
    history.receive(ProviderReading(provider: .claude, outcome: .sample(UsageSample(observedAt: time, windows: [window]))), at: time)
    return history.display(at: time)
}

@Test func trendKeepsChangesAndSparseRepeatsWithinOnePeriod() {
    var trend = UsageTrend()
    let changes = [
        (10.0, start), (10, start), (10, start.addingTimeInterval(60)),
        (12, start.addingTimeInterval(120)), (12, start.addingTimeInterval(120 + 600)),
    ].map { percent, time in trend.record(display(percent, reset: reset, at: time), now: start) }
    #expect(changes == [true, false, false, true, true])
    #expect(trend.points.map(\.percent) == [10, 12, 12])
}

@Test func trendStartsOverForANewPeriodOrHeadline() {
    var trend = UsageTrend()
    trend.record(display(80, reset: reset, at: start), now: start)
    trend.record(display(85, reset: reset, at: start.addingTimeInterval(60)), now: start)
    let later = reset.addingTimeInterval(60)
    trend.record(display(2, reset: reset.addingTimeInterval(5 * 60 * 60), at: later), now: later)
    #expect(trend.points.map(\.percent) == [2])

    trend.record(display(40, reset: nil, at: later.addingTimeInterval(60), id: "spend_limit"), now: later)
    #expect(trend.windowID == "spend_limit")
    #expect(trend.points.map(\.percent) == [40])
}

@Test func trendIsCappedAndStoredPrivately() throws {
    var trend = UsageTrend()
    for index in 0...(UsageTrend.maximumPoints + 10) {
        let time = start.addingTimeInterval(Double(index))
        trend.record(display(Double(index % 100), reset: nil, at: time), now: time)
    }
    #expect(trend.points.count == UsageTrend.maximumPoints)

    let folder = FileManager.default.temporaryDirectory.appending(path: "UsageTrendTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = UsageTrendStore(directory: folder)
    #expect(store.load().isEmpty)
    try store.save([.claude: trend])
    #expect(store.load() == [.claude: trend])
    let attributes = try FileManager.default.attributesOfItem(atPath: folder.appending(path: "trend.json").path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}
