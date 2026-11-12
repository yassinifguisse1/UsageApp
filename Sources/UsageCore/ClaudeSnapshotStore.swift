import Darwin
import Foundation

public struct ClaudeSnapshotStore: Sendable {
    public enum StoreError: Error {
        case unsafeDirectory, invalidSnapshot, fileOperation
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/UsageApp")
    }

    public let directory: URL
    private var snapshotURL: URL { directory.appending(path: "claude-usage.json") }

    public init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    /// nil means the bridge has not successfully recorded a status-line callback yet.
    public func read() throws -> UsageSample? {
        try readState().sample
    }

    /// Also reports when Claude Code last sent rate limits in a shape this version cannot read.
    public func readState() throws -> (sample: UsageSample?, unrecognizedAt: Date?) {
        guard let record = try readRecord() else { return (nil, nil) }
        let windows = ClaudeWindow.allCases.compactMap { kind -> UsageWindow? in
            guard let value = record.windows[kind.rawValue], (0...100).contains(value.usedPercent) else {
                return nil
            }
            return kind.window(
                usedPercent: value.usedPercent,
                resetsAt: ProviderJSON.reset(value.resetsAt)
            )
        }
        return (
            UsageSample(observedAt: Date(timeIntervalSince1970: record.observedAt), windows: windows),
            record.unrecognizedAt.map(Date.init(timeIntervalSince1970:))
        )
    }

    private func readRecord() throws -> Record? {
        let data: Data
        do {
            let file = try FileHandle(forReadingFrom: snapshotURL)
            defer { try? file.close() }
            data = try file.read(upToCount: 4097) ?? Data()
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
        guard data.count <= 4096 else { throw StoreError.invalidSnapshot }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.version == 1, record.observedAt.isFinite, record.observedAt > 0 else {
            throw StoreError.invalidSnapshot
        }
        return record
    }

    public func capture(_ payload: Data, observedAt: Date = Date()) throws {
        let sample = try ClaudeUsageParser.parse(payload, observedAt: observedAt)
        try PrivateFiles.prepare(directory: directory)

        let lockPath = directory.appending(path: ".claude-usage.lock").path
        let lock = open(lockPath, O_CREAT | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw StoreError.fileOperation }
        defer { _ = Darwin.close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw StoreError.fileOperation }

        let windows = sample.windows.reduce(into: [String: Record.Window]()) { result, window in
            result[window.id] = Record.Window(
                usedPercent: window.usedPercent, resetsAt: window.resetsAt?.timeIntervalSince1970
            )
        }
        var record = Record(version: 1, observedAt: sample.observedAt.timeIntervalSince1970, windows: windows)
        let previous = try? readRecord()
        if sample.windows.isEmpty {
            if ClaudeUsageParser.reportsLimits(in: payload) {
                // Keep the last usable reading, but note that the limits arrived in an unknown shape.
                record = Record(
                    version: 1,
                    observedAt: previous?.observedAt ?? record.observedAt,
                    windows: previous?.windows ?? [:],
                    unrecognizedAt: record.observedAt
                )
            } else if previous != nil {
                // A startup callback without limits must not replace or re-date a usable sample.
                return
            }
        } else if let previous, !previous.windows.isEmpty, record.observedAt < previous.observedAt {
            return
        }
        let data = try JSONEncoder().encode(record)
        try PrivateFiles.replace(snapshotURL, with: data)
    }

    private struct Record: Codable {
        struct Window: Codable {
            let usedPercent: Double
            let resetsAt: Double?
        }

        let version: Int
        let observedAt: Double
        let windows: [String: Window]
        var unrecognizedAt: Double?
    }
}
