import Foundation
import UsageCore

/// Asks GitHub for the latest release at most once a day. Sends no identifiers.
@MainActor
final class UpdateChecker {
    private let model: UsageModel
    private let defaults: UserDefaults
    private let session = URLSession(configuration: .ephemeral)
    private var task: Task<Void, Never>?
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    init(model: UsageModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        apply(defaults.data(forKey: "latestReleaseResponse"))
    }

    func checkIfDue(now: Date = Date()) {
        guard model.checksForUpdates, task == nil else { return }
        if let last = defaults.object(forKey: "lastUpdateCheck") as? Date,
           now.timeIntervalSince(last) < UpdateCheck.interval, now >= last {
            if model.availableUpdate == nil { apply(defaults.data(forKey: "latestReleaseResponse")) }
            return
        }
        defaults.set(now, forKey: "lastUpdateCheck")

        var request = URLRequest(url: UpdateCheck.latestReleaseAPI, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        task = Task { [weak self, session] in
            let data = try? await session.data(for: request).0
            guard let self else { return }
            self.task = nil
            guard let data, self.model.checksForUpdates else { return }
            self.defaults.set(data, forKey: "latestReleaseResponse")
            self.apply(data)
        }
    }

    private func apply(_ data: Data?) {
        guard model.checksForUpdates, let data else { return }
        model.availableUpdate = UpdateCheck.newerRelease(in: data, than: currentVersion)
    }
}
