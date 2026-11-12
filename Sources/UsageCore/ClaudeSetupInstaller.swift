import Darwin
import Foundation

public struct ClaudeSetupInstaller: Sendable {
    public enum SetupError: Error, Equatable, LocalizedError {
        case customSettings, managedSettings, unsafeFile, invalidSettings, unsupportedCommand
        case alreadyConfigured, changedSettings, noUndo, helperMissing, writeFailed

        public var errorDescription: String? {
            switch self {
            case .customSettings: "This Claude session uses a custom settings directory. Use manual setup for that directory."
            case .managedSettings: "Claude settings or status-line commands are managed. Check /status or ask your administrator."
            case .unsafeFile: "The settings or helper path is unreadable, has an unexpected owner, or is a symbolic link."
            case .invalidSettings: "Claude settings are not a valid JSON object. Fix the file before reviewing setup again."
            case .unsupportedCommand: "This status line needs manual setup to preserve its command and options."
            case .alreadyConfigured: "This status line already uses the UsageApp helper."
            case .changedSettings: "Claude settings changed. Review the current settings before making another change."
            case .noUndo: "UsageApp could not undo setup. The installed status-line setting has changed or no undo record exists."
            case .helperMissing: "The Claude status-line helper is missing from this UsageApp build."
            case .writeFailed: "UsageApp couldn’t save the Claude settings safely. Check the file permissions and try again."
            }
        }
    }

    public struct Preview: Identifiable, Sendable {
        public let id = UUID()
        public let settingsURL: URL
        public let originalCommand: String?
        public let installedCommand: String
        public var createsSettingsFile: Bool { originalFile == nil }
        fileprivate let originalFile: FileSnapshot?
    }

    public let settingsURL: URL
    public let supportDirectory: URL
    private let bundledHelper: URL?
    private let customConfiguration: Bool
    private let isManaged: @Sendable () -> Bool

    public init(
        settingsURL: URL,
        supportDirectory: URL,
        bundledHelper: URL?,
        customConfiguration: Bool = false,
        isManaged: @escaping @Sendable () -> Bool = { false }
    ) {
        self.settingsURL = settingsURL
        self.supportDirectory = supportDirectory
        self.bundledHelper = bundledHelper
        self.customConfiguration = customConfiguration
        self.isManaged = isManaged
    }

    public static func personal(bundledHelper: URL?) -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = home.appending(path: ".claude", directoryHint: .isDirectory)
        let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map {
            !$0.isEmpty && URL(filePath: $0).standardizedFileURL.path != directory.path
        } ?? false
        return Self(
            settingsURL: directory.appending(path: "settings.json"),
            supportDirectory: ClaudeSnapshotStore.defaultDirectory,
            bundledHelper: bundledHelper, customConfiguration: custom,
            isManaged: { hasManagedSettings() }
        )
    }

    public func preview() throws -> Preview {
        try checkPolicy()
        let file = try readSettings()
        if let file, file.mode & 0o200 == 0 { throw SetupError.unsafeFile }
        let settings = try decodeSettings(file)
        if settings["disableAllHooks"] as? Bool == true { throw SetupError.managedSettings }
        var original: String?
        var replacement = Self.quote(helperURL.path)
        if let statusLine = settings["statusLine"] {
            guard let entry = statusLine as? [String: Any],
                  entry["type"] as? String == "command", let command = entry["command"] as? String else {
                throw SetupError.unsupportedCommand
            }
            if recognizesHelper(command) { throw SetupError.alreadyConfigured }
            let script = try directScript(from: command)
            original = command
            replacement += " -- " + Self.quote(script.path)
        }
        return Preview(
            settingsURL: settingsURL, originalCommand: original,
            installedCommand: replacement, originalFile: file
        )
    }

    public func apply(_ preview: Preview) throws {
        try checkPolicy()
        guard preview.settingsURL == settingsURL, try readSettings() == preview.originalFile else {
            throw SetupError.changedSettings
        }
        guard let bundledHelper, FileManager.default.isExecutableFile(atPath: bundledHelper.path) else {
            throw SetupError.helperMissing
        }
        try withSetupLock {
            let current = try readSettings()
            guard current == preview.originalFile,
                  preview.installedCommand == Self.quote(helperURL.path)
                      || preview.installedCommand.hasPrefix(Self.quote(helperURL.path) + " -- ") else {
                throw SetupError.changedSettings
            }
            var settings = try decodeSettings(current)
            var statusLine = settings["statusLine"] as? [String: Any] ?? ["type": "command"]
            statusLine["command"] = preview.installedCommand
            settings["statusLine"] = statusLine
            let bytes = try encodeSettings(settings)
            try checkDirectory(settingsURL.deletingLastPathComponent(), create: true)
            try checkDirectory(helperURL.deletingLastPathComponent(), privateDirectory: true, create: true)
            try replace(helperURL, with: Data(contentsOf: bundledHelper), mode: 0o700)
            let receipt = Receipt(
                settingsPath: settingsURL.path, installedCommand: preview.installedCommand,
                originalCommand: preview.originalCommand, installedAt: Date()
            )
            // Stage undo first. A receipt is active only when the installed command matches.
            try replace(receiptURL, with: JSONEncoder().encode(receipt), mode: 0o600)
            try replace(settingsURL, with: bytes, mode: current?.mode ?? 0o600) {
                try checkPolicy()
                guard try readSettings() == current else { throw SetupError.changedSettings }
            }
        }
    }

    public func undo() throws {
        try checkPolicy()
        try withSetupLock {
            let current = try readSettings()
            if let current, current.mode & 0o200 == 0 { throw SetupError.unsafeFile }
            var settings = try decodeSettings(current)
            guard let receipt = try readReceipt(),
                  var statusLine = settings["statusLine"] as? [String: Any],
                  statusLine["type"] as? String == "command",
                  statusLine["command"] as? String == receipt.installedCommand else {
                throw SetupError.noUndo
            }
            if let original = receipt.originalCommand {
                statusLine["command"] = original
                settings["statusLine"] = statusLine
            } else {
                // A later edit to a newly created status line cannot be restored to an
                // absent entry without discarding that edit.
                guard statusLine.count == 2 else { throw SetupError.noUndo }
                settings.removeValue(forKey: "statusLine")
            }
            try replace(settingsURL, with: encodeSettings(settings), mode: current?.mode ?? 0o600) {
                try checkPolicy()
                guard try readSettings() == current else { throw SetupError.changedSettings }
            }
            // A leftover receipt would be inactive after a successful restore.
            try? FileManager.default.removeItem(at: receiptURL)
        }
    }

    public func connection() -> ClaudeSetupConnection {
        guard let settings = try? decodeSettings(readSettings()),
              let entry = settings["statusLine"] as? [String: Any],
              entry["type"] as? String == "command",
              let command = entry["command"] as? String else { return .init() }
        if let receipt = try? readReceipt(), receipt.installedCommand == command {
            return .init(isConfigured: true, installedAt: receipt.installedAt)
        }
        return .init(isConfigured: recognizesHelper(command))
    }

    private var helperURL: URL {
        supportDirectory.appending(path: "bin/usageapp-claude-status")
    }

    private var receiptURL: URL { supportDirectory.appending(path: "claude-setup.json") }

    private func checkPolicy() throws {
        if customConfiguration { throw SetupError.customSettings }
        if isManaged() { throw SetupError.managedSettings }
    }

    private static func hasManagedSettings() -> Bool {
        let fm = FileManager.default
        let root = URL(filePath: "/Library/Application Support/ClaudeCode", directoryHint: .isDirectory)
        if fm.fileExists(atPath: root.appending(path: "managed-settings.json").path)
            || fm.fileExists(atPath: root.appending(path: "managed-settings.d").path) {
            return true
        }
        let domain = UserDefaults(suiteName: "com.anthropic.claudecode")
        return ["statusLine", "disableAllHooks", "allowManagedHooksOnly"].contains {
            domain?.objectIsForced(forKey: $0, inDomain: "com.anthropic.claudecode") == true
        }
    }

    private func readSettings() throws -> FileSnapshot? {
        try checkDirectory(settingsURL.deletingLastPathComponent())
        return try read(settingsURL)
    }

    private func readReceipt() throws -> Receipt? {
        try checkDirectory(supportDirectory, privateDirectory: true)
        guard let file = try read(receiptURL), file.mode & 0o077 == 0 else { return nil }
        let receipt = try JSONDecoder().decode(Receipt.self, from: file.data)
        return receipt.settingsPath == settingsURL.path ? receipt : nil
    }

    private func decodeSettings(_ file: FileSnapshot?) throws -> [String: Any] {
        guard let file else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: file.data),
              let settings = object as? [String: Any] else { throw SetupError.invalidSettings }
        return settings
    }

    private func encodeSettings(_ settings: [String: Any]) throws -> Data {
        var bytes = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        bytes.append(10)
        return bytes
    }

    private func recognizesHelper(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = settingsURL.deletingLastPathComponent().deletingLastPathComponent()
        let legacy = home.appending(path: ".local/bin/usageapp-claude-status").path
        let prefixes = [
            Self.quote(helperURL.path), "\"\(helperURL.path)\"", helperURL.path,
            Self.quote(legacy), "\"\(legacy)\"", legacy,
            "\"$HOME/.local/bin/usageapp-claude-status\"", "$HOME/.local/bin/usageapp-claude-status",
            "~/.local/bin/usageapp-claude-status",
        ]
        return prefixes.contains { prefix in
            trimmed == prefix || (trimmed.hasPrefix(prefix) && trimmed.dropFirst(prefix.count).first?.isWhitespace == true)
        }
    }

    private func directScript(from command: String) throws -> URL {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var path = trimmed
        if let quote = trimmed.first, quote == "'" || quote == "\"" {
            guard trimmed.count > 2, trimmed.last == quote else { throw SetupError.unsupportedCommand }
            path = String(trimmed.dropFirst().dropLast())
            guard !path.contains(quote), !path.contains(where: { $0.isNewline || $0 == "\0" }),
                  quote == "'" || !path.contains(where: { "$`\\".contains($0) }) else {
                throw SetupError.unsupportedCommand
            }
        } else {
            guard path.allSatisfy({ $0.isLetter || $0.isNumber || "/._-+~".contains($0) }) else {
                throw SetupError.unsupportedCommand
            }
            if path.hasPrefix("~/") {
                let home = settingsURL.deletingLastPathComponent().deletingLastPathComponent()
                path = home.appending(path: String(path.dropFirst(2))).path
            }
        }
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path),
              let values = try? URL(filePath: path).resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else { throw SetupError.unsupportedCommand }
        let script = URL(filePath: path)
        guard script.lastPathComponent != "usageapp-claude-status" else { throw SetupError.alreadyConfigured }
        return script
    }

    private static func quote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func checkDirectory(_ directory: URL, privateDirectory: Bool = false, create: Bool = false) throws {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            guard errno == ENOENT else { throw SetupError.unsafeFile }
            guard create else { return }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            guard lstat(directory.path, &info) == 0 else { throw SetupError.unsafeFile }
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
              !privateDirectory || info.st_mode & 0o077 == 0 else { throw SetupError.unsafeFile }
    }

    private func read(_ url: URL) throws -> FileSnapshot? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw SetupError.unsafeFile
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1 else { throw SetupError.unsafeFile }
        let limit = 1_048_576
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw SetupError.invalidSettings }
        return FileSnapshot(data: data, mode: info.st_mode & 0o777, inode: info.st_ino)
    }

    private func replace(_ url: URL, with data: Data, mode: mode_t, validate: () throws -> Void = {}) throws {
        var template = Array(url.deletingLastPathComponent().appending(path: ".usageapp-setup.XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw SetupError.writeFailed }
        let temporary = String(decoding: template.dropLast().map(UInt8.init(bitPattern:)), as: UTF8.self)
        defer { _ = unlink(temporary) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        guard fchmod(fd, mode) == 0 else { throw SetupError.writeFailed }
        try handle.synchronize()
        try validate()
        guard rename(temporary, url.path) == 0 else { throw SetupError.writeFailed }
    }

    private func withSetupLock(_ body: () throws -> Void) throws {
        try checkDirectory(supportDirectory, privateDirectory: true, create: true)
        let lock = open(supportDirectory.appending(path: ".claude-setup.lock").path,
                        O_CREAT | O_WRONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw SetupError.unsafeFile }
        defer { _ = Darwin.close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1 else { throw SetupError.unsafeFile }
        while flock(lock, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EINTR else { throw SetupError.writeFailed }
        }
        // Release explicitly even if a concurrent child briefly inherited the descriptor.
        defer { _ = flock(lock, LOCK_UN) }
        try body()
    }

    fileprivate struct FileSnapshot: Equatable, Sendable {
        let data: Data
        let mode: mode_t
        let inode: ino_t
    }

    private struct Receipt: Codable {
        let settingsPath: String
        let installedCommand: String
        let originalCommand: String?
        let installedAt: Date
    }
}
