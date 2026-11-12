import Foundation
import UsageCore

enum DemoUsage {
    static func read(provider: Provider, at date: Date) -> ProviderReading {
        let values: (Double, Double, TimeInterval) = switch provider {
        case .claude: (73, 7, 52 * 60)
        case .codex: (21, 54, 2 * 60 * 60 + 18 * 60)
        }
        let sample = UsageSample(observedAt: date, windows: [
            UsageWindow(id: "short", label: "5-hour window", usedPercent: values.0,
                        resetsAt: date.addingTimeInterval(values.2), isPrimary: true),
            UsageWindow(id: "long", label: "7-day window", usedPercent: values.1,
                        resetsAt: date.addingTimeInterval(3 * 24 * 60 * 60)),
        ])
        return ProviderReading(provider: provider, outcome: .sample(sample))
    }
}
