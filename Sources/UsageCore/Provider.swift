import Foundation

public enum Provider: String, CaseIterable, Sendable {
    case claude, codex, perplexity

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .perplexity: "Perplexity"
        }
    }

    public var unrecognizedFormatMessage: String {
        "\(name) reported usage in a format this version of UsageApp doesn’t recognize. Check for a UsageApp update."
    }

    public var staleAfter: TimeInterval {
        switch self {
        case .claude: 15 * 60
        case .codex: 5 * 60
        case .perplexity: 24 * 60 * 60
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

public enum ProviderSetupAction: Equatable, Sendable {
    case installCodex, signInToCodex, updateCodex
    case configureClaude, startClaude
    case enterPerplexityCredits
}

public struct ProviderReading: Sendable {
    public enum Outcome: Equatable, Sendable {
        case sample(UsageSample)
        case setupRequired(String)
        case waiting(String)
        case unavailable(String)
    }

    public let provider: Provider
    public let outcome: Outcome
    public let setupAction: ProviderSetupAction?

    public init(provider: Provider, outcome: Outcome, setupAction: ProviderSetupAction? = nil) {
        self.provider = provider
        self.outcome = outcome
        self.setupAction = setupAction
    }
}

public protocol UsageProvider: Sendable {
    var provider: Provider { get }
    func read() async -> ProviderReading
}
