import Foundation

public enum ClaudeUsageParser {
    public static func parse(_ data: Data, observedAt: Date) throws -> UsageSample {
        let payload = try ProviderJSON.object(from: data)
        let limits = payload["rate_limits"] as? ProviderJSON.Object ?? [:]
        let windows = ClaudeWindow.allCases.compactMap { kind -> UsageWindow? in
            guard let object = limits[kind.rawValue] as? ProviderJSON.Object,
                  let percent = ProviderJSON.percent(object["used_percentage"]) else { return nil }
            return kind.window(usedPercent: percent, resetsAt: ProviderJSON.reset(object["resets_at"]))
        }
        return UsageSample(observedAt: observedAt, windows: windows)
    }

    /// True when the payload carries rate-limit entries, recognized or not.
    public static func reportsLimits(in data: Data) -> Bool {
        let limits = (try? ProviderJSON.object(from: data))?["rate_limits"] as? ProviderJSON.Object ?? [:]
        return limits.values.contains { ($0 as? ProviderJSON.Object)?.isEmpty == false }
    }
}

enum ClaudeWindow: String, CaseIterable, Codable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case spendLimit = "spend_limit"

    func window(usedPercent: Double, resetsAt: Date?) -> UsageWindow {
        let label: String = switch self {
        case .fiveHour: "5-hour window"
        case .sevenDay: "7-day window"
        case .spendLimit: "Gateway spend limit"
        }
        return UsageWindow(
            id: rawValue,
            label: label,
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            isPrimary: self == .fiveHour
        )
    }
}
