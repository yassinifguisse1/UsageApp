import Foundation
import Testing
import UsageCore

private func withFakeCLI(
    _ source: String,
    body: (URL) async throws -> Void
) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let executable = folder.appending(path: "codex")
    try Data(("#!/bin/sh\n" + source).utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    try await body(executable)
}

@Test func codexReadsAuthenticatedLimitsAcrossAStdioHandshake() async throws {
    try await withFakeCLI(#"""
    [ "$1" = "app-server" ] && [ "$2" = "--listen" ] && [ "$3" = "stdio://" ] || exit 1
    IFS= read -r request || exit 2
    case "$request" in *'"method":"initialize"'*) ;; *) exit 3;; esac
    printf '%s\n' '{"id":1,"result":{"userAgent":"fake"}}'
    IFS= read -r request || exit 4
    case "$request" in *'"method":"initialized"'*) ;; *) exit 5;; esac
    IFS= read -r request || exit 6
    case "$request" in *account*read*false*|*false*account*read*) ;; *) exit 7;; esac
    printf '%s\n' '{"method":"account/updated","params":{}}'
    printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"synthetic@example.invalid"}}}'
    IFS= read -r request || exit 8
    case "$request" in *account*rateLimits*read*) ;; *) exit 9;; esac
    printf '%s' '{"id":3,"result":{"rateLimits":{"primary":'
    printf '%s\n' '{"usedPercent":43,"windowDurationMins":300}}}}'
    """#) { executable in
        let reading = await CodexProvider(executable: executable, timeout: 2).read()
        guard case .sample(let sample) = reading.outcome else {
            Issue.record("Fake Codex should return a sample: \(reading.outcome)")
            return
        }
        #expect(sample.windows.first?.usedPercent == 43)
    }
}

@Test func codexWithoutChatGPTSignInReportsSetupRequired() async throws {
    try await withFakeCLI(#"""
    IFS= read -r request
    printf '%s\n' '{"id":1,"result":{}}'
    IFS= read -r request
    IFS= read -r request
    printf '%s\n' '{"id":2,"result":{"account":null}}'
    """#) { executable in
        let reading = await CodexProvider(executable: executable, timeout: 2).read()
        if case .setupRequired = reading.outcome {} else {
            Issue.record("An unsigned-in CLI should report setup required: \(reading.outcome)")
        }
    }
}

@Test func codexTerminatesAnUnresponsiveStdioSession() async throws {
    try await withFakeCLI(#"""
    while IFS= read -r request; do :; done
    """#) { executable in
        let started = ProcessInfo.processInfo.systemUptime
        let reading = await CodexProvider(executable: executable, timeout: 0.3).read()
        #expect(reading.outcome == .unavailable("Codex did not respond in time. Try Refresh Now."))
        #expect(ProcessInfo.processInfo.systemUptime - started < 2)
    }
}
