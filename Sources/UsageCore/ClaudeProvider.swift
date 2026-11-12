import Foundation

public struct ClaudeProvider: UsageProvider {
    public let provider = Provider.claude
    private let store: ClaudeSnapshotStore

    public init(store: ClaudeSnapshotStore = ClaudeSnapshotStore()) {
        self.store = store
    }

    public func read() async -> ProviderReading {
        let outcome: ProviderReading.Outcome
        do {
            if let sample = try store.read() {
                outcome = sample.windows.isEmpty
                    ? .unavailable("Waiting for Claude Code to report usage after a response in an eligible session.")
                    : .sample(sample)
            } else {
                outcome = .setupRequired("Connect the Claude Code status line using the README.")
            }
        } catch {
            outcome = .unavailable("The Claude Code usage snapshot could not be read.")
        }
        return ProviderReading(provider: provider, outcome: outcome)
    }
}
