import Foundation

public struct UsagePoint: Codable, Equatable, Sendable {
    public let date: Date
    public let percent: Double

    public init(date: Date, percent: Double) {
        self.date = date
        self.percent = percent
    }
}

/// Recent readings of a provider's headline window within its current period.
public struct UsageTrend: Codable, Equatable, Sendable {
    public static let maximumPoints = 500
    public static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    public private(set) var windowID: String?
    public private(set) var resetsAt: Date?
    public private(set) var points: [UsagePoint] = []

    public init(windowID: String? = nil, resetsAt: Date? = nil, points: [UsagePoint] = []) {
        self.windowID = windowID
        self.resetsAt = resetsAt
        self.points = points
    }

    /// Returns true when the trend changed.
    @discardableResult
    public mutating func record(_ display: ProviderDisplay, now: Date) -> Bool {
        guard let headline = display.headline, headline.state == .current,
              let percent = headline.percent, let observedAt = display.observedAt else { return false }

        let newPeriod = headline.id != windowID || {
            guard let resetsAt, let next = headline.resetsAt else { return false }
            return next.timeIntervalSince(resetsAt) > 60
        }()
        if newPeriod {
            self = UsageTrend(windowID: headline.id, resetsAt: headline.resetsAt)
        }
        resetsAt = headline.resetsAt

        if let last = points.last {
            guard observedAt > last.date else { return newPeriod }
            // Claude Code reports often. Keep unchanged readings sparse.
            if last.percent == percent && observedAt.timeIntervalSince(last.date) < 10 * 60 { return newPeriod }
        }
        points.append(UsagePoint(date: observedAt, percent: percent))
        points.removeAll { now.timeIntervalSince($0.date) > Self.maximumAge }
        if points.count > Self.maximumPoints { points.removeFirst(points.count - Self.maximumPoints) }
        return true
    }
}

/// Saves trends in an owner-private file so the sparkline survives relaunch.
public struct UsageTrendStore: Sendable {
    public let directory: URL
    private var fileURL: URL { directory.appending(path: "trend.json") }

    public init(directory: URL = ClaudeSnapshotStore.defaultDirectory) {
        self.directory = directory
    }

    public func load() -> [Provider: UsageTrend] {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([String: UsageTrend].self, from: data) else { return [:] }
        return saved.reduce(into: [:]) { result, item in
            if let provider = Provider(rawValue: item.key) { result[provider] = item.value }
        }
    }

    public func save(_ trends: [Provider: UsageTrend]) throws {
        let saved = Dictionary(uniqueKeysWithValues: trends.map { ($0.key.rawValue, $0.value) })
        try PrivateFiles.prepare(directory: directory)
        try PrivateFiles.replace(fileURL, with: JSONEncoder().encode(saved))
    }
}
