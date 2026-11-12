import Foundation
import Observation
import UsageCore

@MainActor @Observable
final class UsageModel {
    private(set) var isDemo: Bool
    private(set) var codexPath: String?
    private(set) var refreshingCodex = false
    var detailsProvider: Provider?
    private(set) var pinnedProvider: Provider?
    private(set) var perplexitySnapshot: PerplexityCreditSnapshot?
    private(set) var claudeConnection = ClaudeSetupConnection()
    private var displays: [Provider: ProviderDisplay] = [:]
    private var trends: [Provider: UsageTrend] = [:]

    private(set) var alertsEnabled: Bool
    private(set) var alertThreshold: Double
    private(set) var alertsOnReset: Bool
    private(set) var hiddenProviders: Set<Provider>
    private(set) var codexRefreshMinutes: Int
    private(set) var checksForUpdates: Bool
    var availableUpdate: AvailableRelease?

    let claudeInstaller: ClaudeSetupInstaller
    @ObservationIgnored private let readCodex: @Sendable (URL?) async -> ProviderReading
    @ObservationIgnored private let readClaude: @Sendable (ClaudeSetupConnection, Date?) async -> ProviderReading
    @ObservationIgnored var onFirstLiveSetup: (() -> Void)?
    @ObservationIgnored var onAlerts: (([UsageAlert]) -> Void)?
    @ObservationIgnored var onVisibleProvidersChanged: (() -> Void)?
    @ObservationIgnored private let trendStore: UsageTrendStore?
    @ObservationIgnored private var alertTracker: UsageAlertTracker
    @ObservationIgnored private var isVisible = true

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
    @ObservationIgnored private var queuedClaudeRead = false
    @ObservationIgnored private var pendingLiveSetup = false
    @ObservationIgnored private var claudeIgnoreBefore: Date?

    init(
        defaults: UserDefaults = .standard,
        claudeInstaller: ClaudeSetupInstaller = .personal(
            bundledHelper: Bundle.main.url(forAuxiliaryExecutable: "usageapp-claude-status")
        ),
        readCodex: @escaping @Sendable (URL?) async -> ProviderReading = { await CodexProvider(executable: $0).read() },
        readClaude: @escaping @Sendable (ClaudeSetupConnection, Date?) async -> ProviderReading = {
            await ClaudeProvider(connection: $0, ignoreBefore: $1).read()
        },
        trendStore: UsageTrendStore? = nil
    ) {
        self.defaults = defaults
        self.trendStore = trendStore
        trends = trendStore?.load() ?? [:]
        alertsEnabled = defaults.bool(forKey: "alertsEnabled")
        alertThreshold = defaults.object(forKey: "alertThreshold") as? Double ?? 90
        alertsOnReset = defaults.object(forKey: "alertsOnReset") as? Bool ?? true
        alertTracker = defaults.data(forKey: "alertTracker")
            .flatMap { try? JSONDecoder().decode(UsageAlertTracker.self, from: $0) } ?? UsageAlertTracker()
        let hidden = Set((defaults.stringArray(forKey: "hiddenProviders") ?? []).compactMap(Provider.init))
        hiddenProviders = hidden.count < Provider.allCases.count ? hidden : []
        codexRefreshMinutes = defaults.object(forKey: "codexRefreshMinutes") as? Int ?? 2
        checksForUpdates = defaults.object(forKey: "checksForUpdates") as? Bool ?? true
        self.claudeInstaller = claudeInstaller
        self.readCodex = readCodex
        self.readClaude = readClaude
        claudeIgnoreBefore = defaults.object(forKey: "claudeIgnoreReadingsBefore") as? Date
        isDemo = defaults.object(forKey: "demoMode") as? Bool ?? true
        codexPath = defaults.string(forKey: "codexPath")
        if let data = defaults.data(forKey: "perplexityCreditSnapshot"),
           let snapshot = try? JSONDecoder().decode(PerplexityCreditSnapshot.self, from: data),
           snapshot.usedPercent != nil {
            perplexitySnapshot = snapshot
        }
        resetLiveReadings()
        updateDisplays()
    }

    func display(for provider: Provider) -> ProviderDisplay {
        displays[provider] ?? UsageHistory(provider: provider).display(at: now)
    }

    var visibleProviders: [Provider] {
        Provider.allCases.filter { !hiddenProviders.contains($0) }
    }

    func trend(for provider: Provider) -> [UsagePoint] {
        if isDemo { return DemoUsage.trend(provider: provider, at: demoStarted) }
        return trends[provider]?.points ?? []
    }

    func setAlertsEnabled(_ enabled: Bool) {
        alertsEnabled = enabled
        defaults.set(enabled, forKey: "alertsEnabled")
    }

    func setAlertThreshold(_ threshold: Double) {
        alertThreshold = threshold
        defaults.set(threshold, forKey: "alertThreshold")
    }

    func setAlertsOnReset(_ enabled: Bool) {
        alertsOnReset = enabled
        defaults.set(enabled, forKey: "alertsOnReset")
    }

    func setProvider(_ provider: Provider, shown: Bool) {
        var next = hiddenProviders
        if shown { next.remove(provider) } else { next.insert(provider) }
        guard next != hiddenProviders, next.count < Provider.allCases.count else { return }
        hiddenProviders = next
        defaults.set(next.map(\.rawValue).sorted(), forKey: "hiddenProviders")
        onVisibleProvidersChanged?()
    }

    func setCodexRefreshMinutes(_ minutes: Int) {
        codexRefreshMinutes = minutes
        defaults.set(minutes, forKey: "codexRefreshMinutes")
        nextCodexRead = min(nextCodexRead, Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func setChecksForUpdates(_ enabled: Bool) {
        checksForUpdates = enabled
        defaults.set(enabled, forKey: "checksForUpdates")
        if !enabled { availableUpdate = nil }
    }

    private func updateDisplays() {
        var next: [Provider: ProviderDisplay] = [:]
        for provider in Provider.allCases {
            var reading = history[provider] ?? UsageHistory(provider: provider)
            if isDemo {
                reading = UsageHistory(provider: provider)
                reading.receive(DemoUsage.read(provider: provider, at: demoStarted), at: demoStarted)
                next[provider] = reading.display(at: demoStarted)
            } else {
                next[provider] = reading.display(at: now)
            }
        }
        if next != displays { displays = next }
        updateFirstLiveSetup()
    }

    private func resetLiveReadings() {
        history = [:]
        for (provider, message) in [
            (Provider.codex, "Checking the local Codex connection."),
            (Provider.claude, "Checking the Claude Code status line."),
        ] {
            var reading = UsageHistory(provider: provider)
            reading.receive(ProviderReading(provider: provider, outcome: .waiting(message)), at: now)
            history[provider] = reading
        }
        loadPerplexityReading()
    }

    private func updateFirstLiveSetup() {
        guard pendingLiveSetup, !isDemo else { return }
        let decision = LiveSetupDecision.evaluate(
            readings: Array(displays.values),
            checking: codexTask != nil || claudeTask != nil
        )
        guard decision != .wait else { return }
        pendingLiveSetup = false
        defaults.set(true, forKey: "reviewedFirstLiveUsage")
        if decision == .open { onFirstLiveSetup?() }
    }

    func setDemo(_ enabled: Bool) {
        guard isDemo != enabled else { return }
        generation += 1
        isDemo = enabled
        defaults.set(enabled, forKey: "demoMode")
        pendingLiveSetup = !enabled && !defaults.bool(forKey: "reviewedFirstLiveUsage")
        resetLiveReadings()
        queuedCodexRead = false
        queuedClaudeRead = false
        codexTask?.cancel()
        claudeTask?.cancel()
        refresh()
    }

    func setPerplexitySnapshot(_ snapshot: PerplexityCreditSnapshot?) {
        perplexitySnapshot = snapshot
        defaults.set(snapshot.flatMap { try? JSONEncoder().encode($0) }, forKey: "perplexityCreditSnapshot")
        now = Date()
        loadPerplexityReading()
        updateDisplays()
    }

    private func loadPerplexityReading() {
        var reading = UsageHistory(provider: .perplexity)
        let manual = perplexitySnapshot?.reading ?? ProviderReading(
            provider: .perplexity,
            outcome: .setupRequired("Enter your Perplexity Computer plan credits."),
            setupAction: .enterPerplexityCredits
        )
        reading.receive(manual, at: now)
        history[.perplexity] = reading
    }

    func checkCodex() {
        now = Date()
        refreshCodex()
        updateDisplays()
    }

    func checkClaude() {
        now = Date()
        refreshClaude()
        updateDisplays()
    }

    func claudeSetupChanged(wasUndone: Bool) {
        now = Date()
        if wasUndone {
            claudeIgnoreBefore = now
            defaults.set(now, forKey: "claudeIgnoreReadingsBefore")
        }
        var reading = UsageHistory(provider: .claude)
        let outcome: ProviderReading.Outcome = wasUndone
            ? .setupRequired("Connect your Claude Code status line to receive usage.")
            : .waiting("Use Claude Code normally in a trusted project to receive the first reading.")
        reading.receive(ProviderReading(
            provider: .claude, outcome: outcome,
            setupAction: wasUndone ? .configureClaude : .startClaude
        ), at: now)
        history[.claude] = reading
        if wasUndone { claudeConnection = .init() }
        claudeTask?.cancel()
        refreshClaude()
        updateDisplays()
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
        isVisible = visible
        // Notifications need fresh readings while the panel is hidden, at a gentler pace.
        guard visible || alertsEnabled && !isDemo else { return }
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
        nextCodexRead = now.addingTimeInterval(isVisible ? TimeInterval(codexRefreshMinutes * 60) : 10 * 60)
        refreshingCodex = true
        let executable = codexPath.map { URL(filePath: $0) } ?? CodexProvider.findExecutable()
        let fetch = readCodex
        let currentGeneration = generation
        codexTask = Task { [weak self] in
            let reading = await fetch(executable)
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
        guard !isDemo else { return }
        guard claudeTask == nil else {
            if claudeTask?.isCancelled == true { queuedClaudeRead = true }
            return
        }
        nextClaudeRead = now.addingTimeInterval(isVisible ? 5 : 60)
        let installer = claudeInstaller
        let cutoff = claudeIgnoreBefore
        let fetch = readClaude
        let currentGeneration = generation
        claudeTask = Task { [weak self] in
            let (connection, reading) = await Task.detached(priority: .utility) {
                let connection = installer.connection()
                let reading = await fetch(connection, cutoff)
                return (connection, reading)
            }.value
            guard let self else { return }
            self.claudeTask = nil
            if !Task.isCancelled, self.generation == currentGeneration {
                self.claudeConnection = connection
                self.accept(reading)
            }
            if self.queuedClaudeRead {
                self.queuedClaudeRead = false
                self.refreshClaude()
            }
        }
    }

    private func accept(_ reading: ProviderReading) {
        now = Date()
        var providerHistory = history[reading.provider] ?? UsageHistory(provider: reading.provider)
        providerHistory.receive(reading, at: now)
        history[reading.provider] = providerHistory
        updateDisplays()
        guard case .sample = reading.outcome else { return }
        let display = self.display(for: reading.provider)

        if trends[reading.provider, default: UsageTrend()].record(display, now: now) {
            try? trendStore?.save(trends)
        }
        if alertsEnabled {
            let alerts = alertTracker.alerts(
                for: display, thresholds: Array(Set([alertThreshold, 100])),
                includeResets: alertsOnReset, now: now
            )
            defaults.set(try? JSONEncoder().encode(alertTracker), forKey: "alertTracker")
            if !alerts.isEmpty { onAlerts?(alerts) }
        }
    }

    func setPinnedProvider(_ provider: Provider?) {
        pinnedProvider = provider
    }

    func stop() {
        generation += 1
        pendingLiveSetup = false
        queuedCodexRead = false
        queuedClaudeRead = false
        codexTask?.cancel()
        claudeTask?.cancel()
    }
}
