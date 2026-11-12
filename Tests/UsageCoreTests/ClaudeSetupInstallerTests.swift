import Foundation
import Testing
import UsageCore

@Test func claudeSetupReviewsAndRestoresAnExistingScriptWithoutChangingOtherSettings() throws {
    try withClaudeFixture { fixture in
        let script = fixture.home.appending(path: "My status script.sh")
        try fixture.writeExecutable("#!/bin/sh\ncat\n", to: script)
        let command = "\"\(script.path)\""
        try fixture.writeSettings([
            "theme": "dark",
            "statusLine": ["type": "command", "command": command, "padding": 3, "refreshInterval": 60],
        ])
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: fixture.settings.path)
        let original = try Data(contentsOf: fixture.settings)
        let preview = try fixture.installer.preview()
        #expect(preview.originalCommand == command)
        #expect(try Data(contentsOf: fixture.settings) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.support.path))

        try fixture.installer.apply(preview)
        var document = try fixture.readSettings()
        let entry = try #require(document["statusLine"] as? [String: Any])
        #expect(entry["command"] as? String == preview.installedCommand)
        #expect(entry["padding"] as? Int == 3)
        #expect(entry["refreshInterval"] as? Int == 60)
        #expect(document["theme"] as? String == "dark")
        #expect(try fixture.permissions(fixture.settings) == 0o640)
        #expect(try fixture.permissions(fixture.support.appending(path: "claude-setup.json")) == 0o600)
        #expect(fixture.installer.connection().canUndo)
        #expect(throws: ClaudeSetupInstaller.SetupError.alreadyConfigured) { try fixture.installer.preview() }

        // The generated shell command still invokes the exact script path with its stdin and stdout.
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", preview.installedCommand]
        process.standardInput = input
        process.standardOutput = output
        let payload = Data("original output\n".utf8)
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()
        #expect(try output.fileHandleForReading.readToEnd() == payload)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        document["theme"] = "light"
        var changedEntry = entry
        changedEntry["padding"] = 4
        document["statusLine"] = changedEntry
        try fixture.writeSettings(document)
        try fixture.installer.undo()
        let restored = try fixture.readSettings()
        let restoredEntry = try #require(restored["statusLine"] as? [String: Any])
        #expect(restoredEntry["command"] as? String == command)
        #expect(restoredEntry["padding"] as? Int == 4)
        #expect(restored["theme"] as? String == "light")
        #expect(!fixture.installer.connection().isConfigured)
    }
}

@Test func claudeSetupCreatesAndRemovesOnlyItsStatusLine() throws {
    try withClaudeFixture { fixture in
        let preview = try fixture.installer.preview()
        #expect(preview.createsSettingsFile)
        #expect(!FileManager.default.fileExists(atPath: fixture.settings.path))
        try fixture.installer.apply(preview)
        #expect(try fixture.permissions(fixture.settings) == 0o600)
        var settings = try fixture.readSettings()
        settings["theme"] = "dark"
        try fixture.writeSettings(settings)
        try fixture.installer.undo()
        let remaining = try fixture.readSettings()
        #expect(remaining["theme"] as? String == "dark")
        #expect(remaining["statusLine"] == nil)
    }
}

@Test func claudeSetupStopsWhenAReviewedOrInstalledCommandChanges() throws {
    try withClaudeFixture { fixture in
        try fixture.writeSettings(["theme": "dark"])
        let first = try fixture.installer.preview()
        try fixture.writeSettings(["theme": "light"])
        #expect(throws: ClaudeSetupInstaller.SetupError.changedSettings) { try fixture.installer.apply(first) }
        #expect(!FileManager.default.fileExists(atPath: fixture.support.path))

        try fixture.installer.apply(fixture.installer.preview())
        try fixture.writeSettings(["statusLine": ["type": "command", "command": "/bin/date"]])
        let changed = try Data(contentsOf: fixture.settings)
        #expect(throws: ClaudeSetupInstaller.SetupError.noUndo) { try fixture.installer.undo() }
        #expect(try Data(contentsOf: fixture.settings) == changed)
    }
}

@Test func claudeSetupFallsBackForInvalidManagedSymlinkedAndComplexSettings() throws {
    try withClaudeFixture { fixture in
        #expect(throws: ClaudeSetupInstaller.SetupError.managedSettings) {
            try fixture.makeInstaller(isManaged: { true }).preview()
        }
        #expect(throws: ClaudeSetupInstaller.SetupError.customSettings) {
            try fixture.makeInstaller(customConfiguration: true).preview()
        }

        try fixture.writeSettings(["disableAllHooks": true])
        #expect(throws: ClaudeSetupInstaller.SetupError.managedSettings) { try fixture.installer.preview() }

        try fixture.writeSettings(["statusLine": ["type": "command", "command": "/bin/cat | /bin/date"]])
        #expect(throws: ClaudeSetupInstaller.SetupError.unsupportedCommand) { try fixture.installer.preview() }
        try fixture.writeSettings(["statusLine": ["type": "command", "command": "~/.local/bin/usageapp-claude-status -- /bin/cat"]])
        #expect(fixture.installer.connection().isConfigured)
        #expect(throws: ClaudeSetupInstaller.SetupError.alreadyConfigured) { try fixture.installer.preview() }

        try Data("invalid".utf8).write(to: fixture.settings)
        #expect(throws: ClaudeSetupInstaller.SetupError.invalidSettings) { try fixture.installer.preview() }

        let target = fixture.home.appending(path: "do-not-edit.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.removeItem(at: fixture.settings)
        try FileManager.default.createSymbolicLink(at: fixture.settings, withDestinationURL: target)
        #expect(throws: ClaudeSetupInstaller.SetupError.unsafeFile) { try fixture.installer.preview() }
        #expect(try Data(contentsOf: target) == Data("{}".utf8))
    }
}

@Test func claudeSetupRequiresAUsableCallbackAfterInstallation() async throws {
    let root = try makeClaudeFixture()
    defer { try? FileManager.default.removeItem(at: root.home) }
    let installer = root.installer
    let store = ClaudeSnapshotStore(directory: root.support)
    let payload = Data(#"{"rate_limits":{"five_hour":{"used_percentage":38}}}"#.utf8)
    try store.capture(payload, observedAt: Date().addingTimeInterval(-60))
    try installer.apply(installer.preview())
    let connection = installer.connection()
    let installedAt = try #require(connection.installedAt)
    let provider = ClaudeProvider(store: store, connection: connection)
    #expect(await provider.read().setupAction == .startClaude)

    try store.capture(payload, observedAt: installedAt.addingTimeInterval(1))
    let newReading = await provider.read()
    guard case .sample(let sample) = newReading.outcome else {
        Issue.record("Expected a live Claude sample after a new callback")
        return
    }
    #expect(sample.windows.first?.usedPercent == 38)
    #expect(newReading.setupAction == nil)

    try installer.undo()
    let undone = ClaudeProvider(store: store, ignoreBefore: installedAt.addingTimeInterval(2))
    #expect(await undone.read().setupAction == .configureClaude)
}

private struct ClaudeFixture {
    let home: URL
    var settings: URL { home.appending(path: ".claude/settings.json") }
    var support: URL { home.appending(path: "UsageApp Support") }
    var helper: URL { home.appending(path: "bundled helper") }
    var installer: ClaudeSetupInstaller { makeInstaller() }

    func makeInstaller(
        customConfiguration: Bool = false, isManaged: @escaping @Sendable () -> Bool = { false }
    ) -> ClaudeSetupInstaller {
        .init(settingsURL: settings, supportDirectory: support, bundledHelper: helper,
              customConfiguration: customConfiguration, isManaged: isManaged)
    }

    func writeExecutable(_ script: String, to url: URL) throws {
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func writeSettings(_ object: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: settings)
    }

    func readSettings() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings))
        return try #require(object as? [String: Any])
    }

    func permissions(_ file: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
    }
}

private func makeClaudeFixture() throws -> ClaudeFixture {
    let home = FileManager.default.temporaryDirectory.appending(path: "UsageApp's tests \(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
    let fixture = ClaudeFixture(home: home)
    try fixture.writeExecutable("#!/bin/sh\n[ \"$1\" = -- ] && exec \"$2\"\n", to: fixture.helper)
    return fixture
}

private func withClaudeFixture(_ body: (ClaudeFixture) throws -> Void) throws {
    let fixture = try makeClaudeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.home) }
    try body(fixture)
}
