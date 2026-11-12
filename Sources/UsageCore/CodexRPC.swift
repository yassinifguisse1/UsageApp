import Darwin
import Foundation

/// A single read-only stdio session. A deadline covers initialization, auth, and the rate-limit call.
final class CodexRPC {
    enum Failure: Error {
        case timeout, unsupported, protocolError, pipeClosed
    }

    private let executable: URL
    private let deadline: TimeInterval
    private let input = Pipe()
    private let output = Pipe()
    private var pending = Data()

    init(executable: URL, timeout: TimeInterval) {
        self.executable = executable
        deadline = ProcessInfo.processInfo.systemUptime + timeout
    }

    func fetchLimits() throws -> ProviderJSON.Object? {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"]
        // Finder launches with a small PATH. Let wrapper scripts find tools alongside the chosen CLI.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            executable.deletingLastPathComponent().path,
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ].compactMap { $0 }.joined(separator: ":")
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
        defer { stop(process) }

        try send([
            "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "usageapp", "title": "UsageApp", "version": "1.0.0"]],
        ])
        _ = try response(id: 1)
        try send(["method": "initialized"])
        try send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
        let status = try response(id: 2)
        if status["account"] is NSNull { return nil }
        guard let account = status["account"] as? ProviderJSON.Object,
              let type = account["type"] as? String else { throw Failure.protocolError }
        guard type == "chatgpt" else { return nil }
        try send(["id": 3, "method": "account/rateLimits/read"])
        return try response(id: 3)
    }

    private func send(_ object: ProviderJSON.Object) throws {
        try checkDeadline()
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func response(id: Int) throws -> ProviderJSON.Object {
        while true {
            let line = try nextLine()
            guard !line.isEmpty else { continue }
            let message = try ProviderJSON.object(from: line)
            // Notifications and server-initiated requests never satisfy a response.
            guard message["method"] == nil, ProviderJSON.number(message["id"]) == Double(id) else { continue }
            if let error = message["error"] as? ProviderJSON.Object {
                if ProviderJSON.number(error["code"]) == -32601 { throw Failure.unsupported }
                throw Failure.protocolError
            }
            guard let result = message["result"] as? ProviderJSON.Object else { throw Failure.protocolError }
            return result
        }
    }

    private func nextLine() throws -> Data {
        let fd = output.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            try checkDeadline()
            if let newline = pending.firstIndex(of: 10) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                return line
            }
            guard pending.count <= 1_048_576 else { throw Failure.protocolError }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0 && errno != EINTR { throw Failure.pipeClosed }
            if ready <= 0 { continue }
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw Failure.pipeClosed }
            pending.append(contentsOf: bytes.prefix(count))
        }
    }

    private func checkDeadline() throws {
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timeout }
    }

    private func stop(_ process: Process) {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        for _ in 0..<15 where process.isRunning { usleep(10_000) }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
}
