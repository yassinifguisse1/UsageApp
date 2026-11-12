import Foundation

public struct PerplexityCreditSnapshot: Codable, Equatable, Sendable {
    public let remaining: Int
    public let allowance: Int
    public let recordedAt: Date
    public let resetsAt: Date?

    public init(remaining: Int, allowance: Int, recordedAt: Date, resetsAt: Date? = nil) {
        self.remaining = remaining
        self.allowance = allowance
        self.recordedAt = recordedAt
        self.resetsAt = resetsAt
    }

    public var usedPercent: Double? {
        guard allowance > 0, (0...allowance).contains(remaining) else { return nil }
        return Double(allowance - remaining) / Double(allowance) * 100
    }

    public var reading: ProviderReading {
        guard let usedPercent else {
            return ProviderReading(provider: .perplexity, outcome: .unavailable("Enter a valid plan credit balance in Usage & Setup."))
        }
        let window = UsageWindow(
            id: "computer-plan-credits", label: "Computer plan credits",
            usedPercent: usedPercent, resetsAt: resetsAt, isPrimary: true
        )
        return ProviderReading(
            provider: .perplexity,
            outcome: .sample(UsageSample(observedAt: recordedAt, windows: [window]))
        )
    }
}
