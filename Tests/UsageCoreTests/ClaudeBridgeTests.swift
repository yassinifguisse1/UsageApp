import Foundation
import Testing
import UsageCore

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    return folder
}

@Test func bridgePreservesExactStdinStdoutStderrAndExitStatusAndOnlyStoresUsage() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClaudeSnapshotStore(directory: folder)
    let payload = Data(#"""
    {
      "session_id": "private-session",
      "transcript_path": "/private/transcript",
      "rate_limits": {"five_hour": {"used_percentage": 17, "resets_at": 1781654400, "extra": "secret"}}
    }
    """#.utf8) + Data([10, 10])
    let stdout = Pipe()
    let stderr = Pipe()
    let command = ["/bin/sh", "-c", "/bin/cat; printf 'original error\n' >&2; exit 23"]

    let status = try ClaudeStatusCommand.run(
        payload: payload, command: command, store: store,
        stdout: stdout.fileHandleForWriting, stderr: stderr.fileHandleForWriting
    )
    try stdout.fileHandleForWriting.close()
    try stderr.fileHandleForWriting.close()
    #expect(status == 23)
    #expect(try stdout.fileHandleForReading.readToEnd() == payload)
    #expect(try stderr.fileHandleForReading.readToEnd() == Data("original error\n".utf8))

    let path = folder.appending(path: "claude-usage.json")
    let data = try Data(contentsOf: path)
    let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(record.keys) == ["version", "observedAt", "windows"])
    let windows = try #require(record["windows"] as? [String: [String: Any]])
    #expect(Set(windows.keys) == ["five_hour"])
    #expect(Set(try #require(windows["five_hour"]).keys) == ["usedPercent", "resetsAt"])
    #expect(try store.read()?.windows.first?.usedPercent == 17)
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}

@Test func missingAndEmptyClaudeCallbacksDoNotFakeOrRedateAReading() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClaudeSnapshotStore(directory: folder)
    let provider = ClaudeProvider(store: store)
    let now = Date()
    let noLimits = Data(#"{"model":{"id":"test"}}"#.utf8)

    if case .setupRequired = await provider.read().outcome {} else {
        Issue.record("Missing bridge file should report setup required.")
    }
    try store.capture(noLimits, observedAt: now)
    if case .waiting = await provider.read().outcome {} else {
        Issue.record("An empty callback should report waiting for data.")
    }

    let real = Data(#"{"rate_limits":{"seven_day":{"used_percentage":0}}}"#.utf8)
    try store.capture(real, observedAt: now)
    let captured = try store.read()
    let original = try #require(captured)
    try store.capture(noLimits, observedAt: now.addingTimeInterval(100))
    try store.capture(real, observedAt: now.addingTimeInterval(-10))
    #expect(try store.read() == original)
    #expect(original.windows.first?.usedPercent == 0)
}

@Test func unrecognizedClaudeLimitsKeepTheLastReadingAndExplainTheGap() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ClaudeSnapshotStore(directory: folder)
    let provider = ClaudeProvider(store: store)
    let now = Date()

    try store.capture(Data(#"{"rate_limits":{"five_hour":{"used_percentage":40}}}"#.utf8), observedAt: now)
    let original = try #require(try store.read())
    try store.capture(Data(#"{"rate_limits":{"five_hour":{"used":41}}}"#.utf8), observedAt: now.addingTimeInterval(60))
    #expect(try store.read() == original)
    #expect(await provider.read().outcome == .unavailable(Provider.claude.unrecognizedFormatMessage))

    try store.capture(Data(#"{"rate_limits":{"five_hour":{"used_percentage":42}}}"#.utf8), observedAt: now.addingTimeInterval(120))
    #expect(try store.readState().unrecognizedAt == nil)
    if case .sample(let sample) = await provider.read().outcome {
        #expect(sample.windows.first?.usedPercent == 42)
    } else {
        Issue.record("A recognized callback should clear the format warning.")
    }
}

@Test func aCaptureFailureDoesNotBreakTheOriginalCommand() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let status = try ClaudeStatusCommand.run(
        payload: Data("bad input".utf8),
        command: ["/bin/sh", "-c", "exit 42"],
        store: ClaudeSnapshotStore(directory: folder),
        stdout: .nullDevice,
        stderr: .nullDevice
    )
    #expect(status == 42)
}
