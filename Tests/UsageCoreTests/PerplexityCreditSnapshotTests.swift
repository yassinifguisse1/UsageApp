import Foundation
import Testing
import UsageCore

@Test func perplexityConvertsRemainingCreditsToUsage() {
    let now = Date()
    let snapshot = PerplexityCreditSnapshot(remaining: 70, allowance: 100, recordedAt: now)
    #expect(snapshot.usedPercent == 30)
    #expect(PerplexityCreditSnapshot(remaining: 100, allowance: 100, recordedAt: now).usedPercent == 0)
    #expect(PerplexityCreditSnapshot(remaining: 0, allowance: 100, recordedAt: now).usedPercent == 100)
    #expect(PerplexityCreditSnapshot(remaining: 0, allowance: 0, recordedAt: now).usedPercent == nil)
    #expect(PerplexityCreditSnapshot(remaining: 101, allowance: 100, recordedAt: now).usedPercent == nil)
    #expect(PerplexityCreditSnapshot(remaining: -1, allowance: 100, recordedAt: now).usedPercent == nil)
}

@Test func perplexityPreservesTheManualReadingTimeAndExpiresAtTheEnteredReset() throws {
    let now = Date()
    let reset = now.addingTimeInterval(60)
    let snapshot = PerplexityCreditSnapshot(remaining: 50, allowance: 100, recordedAt: now, resetsAt: reset)
    let restored = try JSONDecoder().decode(PerplexityCreditSnapshot.self, from: JSONEncoder().encode(snapshot))
    var history = UsageHistory(provider: .perplexity)
    history.receive(restored.reading, at: now)
    #expect(history.display(at: now).observedAt == now)
    #expect(history.display(at: now).headline?.percent == 50)
    #expect(history.display(at: reset).state == .awaitingReset)
    #expect(history.display(at: reset).headline?.percent == nil)
}
