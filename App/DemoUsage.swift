import Foundation
import UsageCore

enum DemoUsage {
    static func read(provider: Provider, at date: Date) -> ProviderReading {
        if provider == .perplexity {
            return PerplexityCreditSnapshot(
                remaining: 48, allowance: 100, recordedAt: date,
                resetsAt: date.addingTimeInterval(12 * 24 * 60 * 60)
            ).reading
        }
        let values: (Double, Double, TimeInterval) = provider == .claude
            ? (73, 7, 52 * 60)
            : (21, 54, 2 * 60 * 60 + 18 * 60)
        let sample = UsageSample(observedAt: date, windows: [
            UsageWindow(id: "short", label: "5-hour window", usedPercent: values.0,
                        resetsAt: date.addingTimeInterval(values.2), isPrimary: true),
            UsageWindow(id: "long", label: "7-day window", usedPercent: values.1,
                        resetsAt: date.addingTimeInterval(3 * 24 * 60 * 60)),
        ])
        return ProviderReading(provider: provider, outcome: .sample(sample))
    }

    /// A plausible climb to the demo headline over the last few hours.
    static func trend(provider: Provider, at date: Date) -> [UsagePoint] {
        guard provider != .perplexity,
              case .sample(let sample) = read(provider: provider, at: date).outcome,
              let headline = sample.windows.first(where: \.isPrimary) else { return [] }
        let steps = [0, 0.08, 0.15, 0.31, 0.38, 0.52, 0.6, 0.66, 0.81, 0.9, 1]
        return steps.enumerated().map { index, fraction in
            UsagePoint(
                date: date.addingTimeInterval(Double(index - steps.count + 1) * 20 * 60),
                percent: headline.usedPercent * fraction
            )
        }
    }
}
