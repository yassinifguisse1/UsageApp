import Foundation

public enum Provider: String, CaseIterable, Sendable {
    case claude, codex

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var staleAfter: TimeInterval {
        switch self {
        case .claude: 15 * 60
        case .codex: 5 * 60
        }
    }
}

public struct UsageWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let isPrimary: Bool

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?, isPrimary: Bool = false) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.isPrimary = isPrimary
    }
}

public struct UsageSample: Equatable, Sendable {
    public let observedAt: Date
    public let windows: [UsageWindow]

    public init(observedAt: Date, windows: [UsageWindow]) {
        self.observedAt = observedAt
        self.windows = windows
    }
}

public struct ProviderReading: Sendable {
    public enum Outcome: Equatable, Sendable {
        case sample(UsageSample)
        case setupRequired(String)
        case unavailable(String)
    }

    public let provider: Provider
    public let outcome: Outcome

    public init(provider: Provider, outcome: Outcome) {
        self.provider = provider
        self.outcome = outcome
    }
}

public protocol UsageProvider: Sendable {
    var provider: Provider { get }
    func read() async -> ProviderReading
}
