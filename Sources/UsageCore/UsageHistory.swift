import Foundation

public enum UsageState: String, Equatable, Sendable {
    case current = "Current"
    case setupRequired = "Setup required"
    case unavailable = "Unavailable"
    case stale = "Stale"
    case awaitingReset = "Awaiting reset update"
}

public struct WindowDisplay: Identifiable, Equatable, Sendable {
    public var id: String { window.id }
    public var label: String { window.label }
    public var percent: Double? { state == .awaitingReset ? nil : window.usedPercent }
    public var resetsAt: Date? { window.resetsAt }

    public let window: UsageWindow
    public let state: UsageState
}

public struct ProviderDisplay: Equatable, Sendable {
    public let provider: Provider
    public let observedAt: Date?
    public let headline: WindowDisplay?
    public let windows: [WindowDisplay]
    public let state: UsageState
    public let message: String?
}

public struct UsageHistory: Equatable, Sendable {
    private let provider: Provider
    private var outcome: ProviderReading.Outcome
    private var lastSample: UsageSample?
    // A provider can drop the old window at reset. Remember it until a new period is reported.
    private var expiredWindows: [UsageWindow] = []

    public init(provider: Provider) {
        self.provider = provider
        outcome = .unavailable("Waiting for a reading.")
    }

    public mutating func receive(_ reading: ProviderReading, at now: Date) {
        guard reading.provider == provider else { return }

        switch reading.outcome {
        case .setupRequired:
            lastSample = nil
            expiredWindows = []
        case .unavailable:
            break
        case .sample(let sample):
            if let lastSample, sample.observedAt < lastSample.observedAt { return }
            recordExpiredWindows(at: now)
            expiredWindows.removeAll { previous in
                sample.windows.contains { window in
                    window.id == previous.id && window.resetsAt.map { $0 > now } == true
                }
            }
            // A missing reset cannot prove that a window whose reset passed has started again.
            let waiting = Set(expiredWindows.map(\.id))
            lastSample = UsageSample(
                observedAt: sample.observedAt,
                windows: sample.windows.filter { !waiting.contains($0.id) }
            )
        }
        outcome = reading.outcome
    }

    public mutating func recordExpiredWindows(at now: Date) {
        guard let lastSample else { return }
        for window in lastSample.windows where window.resetsAt.map({ $0 <= now }) == true {
            if !expiredWindows.contains(where: { $0.id == window.id }) {
                expiredWindows.append(window)
            }
        }
    }

    public func display(at now: Date) -> ProviderDisplay {
        let message: String?
        let fallback: UsageState
        switch outcome {
        case .setupRequired(let reason):
            fallback = .setupRequired
            message = reason
        case .unavailable(let reason):
            fallback = lastSample == nil ? .unavailable : .stale
            message = reason
        case .sample:
            fallback = .unavailable
            message = nil
        }

        let isStale = fallback == .stale || lastSample.map {
            now.timeIntervalSince($0.observedAt) >= provider.staleAfter
        } == true
        let waiting = Set(expiredWindows.map(\.id))
        var windows = (lastSample?.windows ?? []).filter { !waiting.contains($0.id) }.map { window in
            let expired = window.resetsAt.map { $0 <= now } == true
            return WindowDisplay(window: window, state: expired ? .awaitingReset : isStale ? .stale : .current)
        }
        windows += expiredWindows.map { WindowDisplay(window: $0, state: .awaitingReset) }
        let headline = windows.first { $0.window.isPrimary } ?? windows.first { $0.percent != nil } ?? windows.first

        return ProviderDisplay(
            provider: provider,
            observedAt: lastSample?.observedAt,
            headline: headline,
            windows: windows,
            state: headline?.state ?? fallback,
            message: message
        )
    }
}
