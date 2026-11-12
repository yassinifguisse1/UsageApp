import Foundation
import Observation
import UsageCore

@MainActor @Observable
final class UsageModel {
    private(set) var isDemo: Bool
    private(set) var codexPath: String?
    private(set) var refreshingCodex = false
    private(set) var pinnedProvider: Provider?
    private var displays: [Provider: ProviderDisplay] = [:]

    @ObservationIgnored private var now = Date()
    @ObservationIgnored private var demoStarted = Date()
    @ObservationIgnored private var history: [Provider: UsageHistory] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var nextCodexRead = Date.distantPast
    @ObservationIgnored private var nextClaudeRead = Date.distantPast
    @ObservationIgnored private var codexTask: Task<Void, Never>?
    @ObservationIgnored private var claudeTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var queuedCodexRead = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isDemo = defaults.object(forKey: "demoMode") as? Bool ?? true
        codexPath = defaults.string(forKey: "codexPath")
        updateDisplays()
    }

    func display(for provider: Provider) -> ProviderDisplay {
        displays[provider] ?? UsageHistory(provider: provider).display(at: now)
    }

    private func updateDisplays() {
        var next: [Provider: ProviderDisplay] = [:]
        for provider in Provider.allCases {
            var reading = history[provider] ?? UsageHistory(provider: provider)
            if isDemo {
                reading = UsageHistory(provider: provider)
                reading.receive(DemoUsage.read(provider: provider, at: demoStarted), at: now)
            }
            next[provider] = reading.display(at: now)
        }
        if next != displays { displays = next }
    }

    func setDemo(_ enabled: Bool) {
        guard isDemo != enabled else { return }
        generation += 1
        isDemo = enabled
        defaults.set(enabled, forKey: "demoMode")
        history = [:]
        queuedCodexRead = false
        codexTask?.cancel()
        claudeTask?.cancel()
        refresh()
    }

    func setCodexExecutable(_ url: URL?) {
        codexPath = url?.path
        defaults.set(codexPath, forKey: "codexPath")
        history[.codex] = nil
        if !isDemo {
            queuedCodexRead = codexTask != nil
            codexTask?.cancel()
            refresh()
        }
    }

    func tick(visible: Bool) {
        now = Date()
        guard visible else { return }
        if !isDemo {
            for provider in Provider.allCases {
                history[provider]?.recordExpiredWindows(at: now)
            }
        }
        updateDisplays()
        guard !isDemo else { return }
        if now >= nextCodexRead { refreshCodex() }
        if now >= nextClaudeRead { refreshClaude() }
    }

    func refresh() {
        now = Date()
        if isDemo {
            demoStarted = now
        } else {
            refreshCodex()
            refreshClaude()
        }
        updateDisplays()
    }

    private func refreshCodex() {
        guard !isDemo else { return }
        guard codexTask == nil else {
            if codexTask?.isCancelled == true { queuedCodexRead = true }
            return
        }
        nextCodexRead = now.addingTimeInterval(120)
        refreshingCodex = true
        let executable = codexPath.map { URL(filePath: $0) } ?? CodexProvider.findExecutable()
        let adapter = CodexProvider(executable: executable)
        let currentGeneration = generation
        codexTask = Task { [weak self] in
            let reading = await adapter.read()
            guard let self else { return }
            self.codexTask = nil
            self.refreshingCodex = false
            if !Task.isCancelled, self.generation == currentGeneration {
                self.accept(reading)
            }
            if self.queuedCodexRead {
                self.queuedCodexRead = false
                self.refreshCodex()
            }
        }
    }

    private func refreshClaude() {
        guard !isDemo, claudeTask == nil else { return }
        nextClaudeRead = now.addingTimeInterval(5)
        let adapter = ClaudeProvider()
        let currentGeneration = generation
        claudeTask = Task { [weak self] in
            let reading = await adapter.read()
            guard let self else { return }
            self.claudeTask = nil
            if !Task.isCancelled, self.generation == currentGeneration {
                self.accept(reading)
            }
        }
    }

    private func accept(_ reading: ProviderReading) {
        now = Date()
        var providerHistory = history[reading.provider] ?? UsageHistory(provider: reading.provider)
        providerHistory.receive(reading, at: now)
        history[reading.provider] = providerHistory
        updateDisplays()
    }

    func setPinnedProvider(_ provider: Provider?) {
        pinnedProvider = provider
    }

    func stop() {
        generation += 1
        queuedCodexRead = false
        codexTask?.cancel()
        claudeTask?.cancel()
    }
}
