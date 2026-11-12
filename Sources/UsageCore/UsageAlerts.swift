import Foundation

public struct UsageAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case reached(Double)
        case reset
    }

    public let provider: Provider
    public let window: UsageWindow
    public let kind: Kind
}

/// Announces each threshold once per window period, and optionally the start of the next period.
public struct UsageAlertTracker: Codable, Equatable, Sendable {
    private struct Entry: Codable, Equatable {
        var threshold: Double
        var resetsAt: Date?
    }

    // Keyed by provider and window ID. Holds the highest threshold announced in the current period.
    private var announced: [String: Entry] = [:]

    public init() {}

    public mutating func alerts(
        for display: ProviderDisplay, thresholds: [Double], includeResets: Bool, now: Date
    ) -> [UsageAlert] {
        var alerts: [UsageAlert] = []
        for item in display.windows where item.state == .current {
            guard let percent = item.percent else { continue }
            let key = "\(display.provider.rawValue)/\(item.id)"

            if let entry = announced[key], startsNewPeriod(item.window, after: entry, thresholds: thresholds) {
                announced[key] = nil
                if includeResets {
                    alerts.append(UsageAlert(provider: display.provider, window: item.window, kind: .reset))
                }
            }

            guard let crossed = thresholds.filter({ percent >= $0 }).max(),
                  crossed > announced[key]?.threshold ?? 0 else { continue }
            announced[key] = Entry(threshold: crossed, resetsAt: item.resetsAt)
            alerts.append(UsageAlert(provider: display.provider, window: item.window, kind: .reached(crossed)))
        }
        // A window that disappears for good should not be remembered forever.
        announced = announced.filter { _, entry in
            entry.resetsAt.map { now.timeIntervalSince($0) < 8 * 24 * 60 * 60 } ?? true
        }
        return alerts
    }

    private func startsNewPeriod(_ window: UsageWindow, after entry: Entry, thresholds: [Double]) -> Bool {
        if let previous = entry.resetsAt, let next = window.resetsAt {
            // Reported reset times can shift by a few seconds within the same period.
            return next.timeIntervalSince(previous) > 60
        }
        // Without reset times, only a drop below every threshold shows that a period ended.
        return window.usedPercent < thresholds.min() ?? 0
    }
}
