#if !SWIFT_PACKAGE
import Foundation
import Testing
import UsageCore

@MainActor
@Test func firstLiveSwitchShowsSetupOnceAndUsesOnlyRealProviderReadings() async throws {
    let (defaults, cleanup) = try isolatedDefaults()
    defer { cleanup() }
    let codex = DeferredProvider()
    let claude = DeferredProvider()
    let model = UsageModel(
        defaults: defaults, claudeInstaller: testInstaller(),
        readCodex: { _ in await codex.read() },
        readClaude: { _, _ in await claude.read() }
    )
    defer { model.stop() }
    var opened = 0
    model.onFirstLiveSetup = { opened += 1 }

    #expect(model.display(for: .codex).headline?.percent != nil)
    model.setDemo(false)
    #expect(opened == 1)
    #expect(model.display(for: .codex).headline == nil)
    #expect(model.display(for: .claude).headline == nil)
    await codex.resolve(liveSample(.codex, percent: 36))
    await claude.resolve(ProviderReading(
        provider: .claude, outcome: .waiting("Waiting for Claude Code"), setupAction: .startClaude
    ))
    #expect(await eventually {
        model.display(for: .codex).headline?.percent == 36 && model.display(for: .claude).state == .waiting
    })
    #expect(model.display(for: .perplexity).setupAction == .enterPerplexityCredits)
    model.setDemo(true)
    model.setDemo(false)
    #expect(await eventually { model.display(for: .codex).headline?.percent == 36 })
    #expect(opened == 1)
}

@MainActor
@Test func whenCodexIsTheOnlyUnresolvedProviderSetupWaitsForItsFirstCheck() async throws {
    let (defaults, cleanup) = try isolatedDefaults()
    defer { cleanup() }
    let codex = DeferredProvider()
    let model = UsageModel(
        defaults: defaults, claudeInstaller: testInstaller(),
        readCodex: { _ in await codex.read() },
        readClaude: { _, _ in liveSample(.claude, percent: 41) }
    )
    defer { model.stop() }
    model.setPerplexitySnapshot(.init(remaining: 80, allowance: 100, recordedAt: Date()))
    var opened = 0
    model.onFirstLiveSetup = { opened += 1 }

    model.setDemo(false)
    #expect(await eventually { model.display(for: .claude).headline?.percent == 41 })
    #expect(model.display(for: .codex).state == .waiting)
    #expect(opened == 0)
    await codex.resolve(ProviderReading(
        provider: .codex, outcome: .setupRequired("Sign in to Codex"), setupAction: .signInToCodex
    ))
    #expect(await eventually { opened == 1 })
}

@MainActor
@Test func aSavedPerplexityReadingSurvivesRelaunchAndBackgroundChecksNeverOpenSetup() async throws {
    let (defaults, cleanup) = try isolatedDefaults()
    defer { cleanup() }
    defaults.set(false, forKey: "demoMode")
    let first = UsageModel(defaults: defaults, claudeInstaller: testInstaller())
    let snapshot = PerplexityCreditSnapshot(remaining: 40, allowance: 80, recordedAt: Date())
    first.setPerplexitySnapshot(snapshot)

    let relaunched = UsageModel(
        defaults: defaults, claudeInstaller: testInstaller(),
        readCodex: { _ in .init(provider: .codex, outcome: .setupRequired("Install Codex"), setupAction: .installCodex) },
        readClaude: { _, _ in .init(provider: .claude, outcome: .setupRequired("Set up Claude"), setupAction: .configureClaude) }
    )
    defer { relaunched.stop() }
    var opened = 0
    relaunched.onFirstLiveSetup = { opened += 1 }
    relaunched.refresh()

    #expect(relaunched.perplexitySnapshot == snapshot)
    #expect(relaunched.display(for: .perplexity).headline?.percent == 50)
    #expect(relaunched.display(for: .perplexity).observedAt == snapshot.recordedAt)
    #expect(await eventually { relaunched.display(for: .codex).setupAction == .installCodex })
    #expect(opened == 0)
}

@MainActor
@Test func anAlreadyConnectedFirstSwitchDoesNotOpenSetup() async throws {
    let (defaults, cleanup) = try isolatedDefaults()
    defer { cleanup() }
    let model = UsageModel(
        defaults: defaults, claudeInstaller: testInstaller(),
        readCodex: { _ in liveSample(.codex, percent: 10) },
        readClaude: { _, _ in liveSample(.claude, percent: 20) }
    )
    defer { model.stop() }
    model.setPerplexitySnapshot(.init(remaining: 70, allowance: 100, recordedAt: Date()))
    var opened = 0
    model.onFirstLiveSetup = { opened += 1 }
    model.setDemo(false)

    #expect(await eventually { defaults.bool(forKey: "reviewedFirstLiveUsage") })
    #expect(opened == 0)
    #expect(model.display(for: .codex).headline?.percent == 10)
    #expect(model.display(for: .claude).headline?.percent == 20)
}

@MainActor
@Test func liveReadingsAlertOnceAndPreferencesPersist() async throws {
    let (defaults, cleanup) = try isolatedDefaults()
    defer { cleanup() }
    defaults.set(false, forKey: "demoMode")
    defaults.set(true, forKey: "reviewedFirstLiveUsage")
    let model = UsageModel(
        defaults: defaults, claudeInstaller: testInstaller(),
        readCodex: { _ in liveSample(.codex, percent: 93) },
        readClaude: { _, _ in liveSample(.claude, percent: 20) }
    )
    defer { model.stop() }
    var alerts: [UsageAlert] = []
    model.onAlerts = { alerts += $0 }
    model.setAlertsEnabled(true)
    model.refresh()
    #expect(await eventually { alerts.map(\.provider) == [.codex] })
    model.refresh()
    try await Task.sleep(for: .milliseconds(100))
    #expect(alerts.count == 1)
    #expect(alerts.first?.kind == .reached(90))

    model.setProvider(.claude, shown: false)
    model.setProvider(.codex, shown: false)
    model.setProvider(.perplexity, shown: false)
    #expect(model.visibleProviders == [.perplexity])
    let restored = UsageModel(defaults: defaults, claudeInstaller: testInstaller())
    #expect(restored.visibleProviders == [.perplexity])
    #expect(restored.alertsEnabled)
}

private actor DeferredProvider {
    private var result: ProviderReading?
    private var pending: [CheckedContinuation<ProviderReading, Never>] = []

    func read() async -> ProviderReading {
        if let result { return result }
        return await withCheckedContinuation { pending.append($0) }
    }

    func resolve(_ reading: ProviderReading) {
        result = reading
        pending.forEach { $0.resume(returning: reading) }
        pending = []
    }
}

private func liveSample(_ provider: Provider, percent: Double) -> ProviderReading {
    ProviderReading(provider: provider, outcome: .sample(UsageSample(
        observedAt: Date(),
        windows: [UsageWindow(id: "fixture", label: "Test window", usedPercent: percent, resetsAt: nil)]
    )))
}

private func isolatedDefaults() throws -> (UserDefaults, () -> Void) {
    let suite = "UsageApp.LiveSetupTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    return (defaults, { defaults.removePersistentDomain(forName: suite) })
}

private func testInstaller() -> ClaudeSetupInstaller {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return .init(
        settingsURL: directory.appending(path: "settings.json"),
        supportDirectory: directory, bundledHelper: nil
    )
}

@MainActor
private func eventually(_ check: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(3)
    while !check(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return check()
}
#endif
