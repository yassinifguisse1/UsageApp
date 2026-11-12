import Foundation

public struct ClaudeProvider: UsageProvider {
    public let provider = Provider.claude
    private let store: ClaudeSnapshotStore
    private let connection: ClaudeSetupConnection
    private let ignoreBefore: Date?

    public init(
        store: ClaudeSnapshotStore = ClaudeSnapshotStore(),
        connection: ClaudeSetupConnection = .init(),
        ignoreBefore: Date? = nil
    ) {
        self.store = store
        self.connection = connection
        self.ignoreBefore = ignoreBefore
    }

    public func read() async -> ProviderReading {
        do {
            let sample = try store.read()
            let cutoff = [ignoreBefore, connection.installedAt].compactMap { $0 }.max()
            if let sample, !sample.windows.isEmpty, cutoff.map({ sample.observedAt > $0 }) ?? true {
                return ProviderReading(provider: provider, outcome: .sample(sample))
            }
            if connection.isConfigured || sample.map({ $0.windows.isEmpty && cutoff == nil }) == true {
                return ProviderReading(
                    provider: provider,
                    outcome: .waiting("Use Claude Code normally in a trusted project. An eligible session reports usage after its first assistant response."),
                    setupAction: .startClaude
                )
            }
            return ProviderReading(
                provider: provider,
                outcome: .setupRequired("Connect your Claude Code status line to receive usage."),
                setupAction: .configureClaude
            )
        } catch {
            return ProviderReading(provider: provider, outcome: .unavailable("The Claude Code usage snapshot could not be read."))
        }
    }
}
