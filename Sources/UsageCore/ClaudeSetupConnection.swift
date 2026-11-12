import Foundation

public struct ClaudeSetupConnection: Equatable, Sendable {
    public let isConfigured: Bool
    public let installedAt: Date?
    public var canUndo: Bool { installedAt != nil }

    public init(isConfigured: Bool = false, installedAt: Date? = nil) {
        self.isConfigured = isConfigured
        self.installedAt = installedAt
    }
}
