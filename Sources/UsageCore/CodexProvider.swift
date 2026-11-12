import Foundation

public struct CodexProvider: UsageProvider {
    public let provider = Provider.codex
    public let executable: URL?
    private let timeout: TimeInterval

    public init(executable: URL?, timeout: TimeInterval = 12) {
        self.executable = executable
        self.timeout = timeout
    }

    public static func findExecutable(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> URL? {
        let standard = [
            home.appending(path: ".local/bin/codex"),
            home.appending(path: ".cargo/bin/codex"),
            URL(filePath: "/opt/homebrew/bin/codex"),
            URL(filePath: "/usr/local/bin/codex"),
            URL(filePath: "/opt/local/bin/codex"),
        ]
        let fromPath = (path ?? "").split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(filePath: String($0), directoryHint: .isDirectory).appending(path: "codex") }
        return (standard + fromPath).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func read() async -> ProviderReading {
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
            return ProviderReading(provider: provider, outcome: .setupRequired(
                "Install the Codex CLI or choose its executable in Usage & Setup."
            ))
        }

        let worker = Task.detached(priority: .utility) {
            Self.fetch(executable: executable, timeout: timeout)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func fetch(executable: URL, timeout: TimeInterval) -> ProviderReading {
        let outcome: ProviderReading.Outcome
        do {
            let result = try CodexRPC(executable: executable, timeout: timeout).fetchLimits()
            if let result {
                let windows = CodexUsageParser.windows(from: result)
                outcome = windows.isEmpty
                    ? .unavailable("Codex did not report any allowance windows for this account.")
                    : .sample(UsageSample(observedAt: Date(), windows: windows))
            } else {
                outcome = .setupRequired("Run codex login in Terminal and sign in with ChatGPT.")
            }
        } catch CodexRPC.Failure.timeout {
            outcome = .unavailable("Codex did not respond in time. Try Refresh Now.")
        } catch CodexRPC.Failure.unsupported {
            outcome = .unavailable("Update the Codex CLI to a version that supports account rate limits.")
        } catch {
            outcome = .unavailable("Codex could not read account limits. Check the CLI sign-in and try again.")
        }
        return ProviderReading(provider: .codex, outcome: outcome)
    }
}
