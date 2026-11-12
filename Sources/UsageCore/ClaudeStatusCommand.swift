import Darwin
import Foundation

public enum ClaudeStatusCommand {
    /// The caller supplies the command explicitly. It receives the original bytes on its own stdin.
    public static func run(
        payload: Data,
        command: [String],
        store: ClaudeSnapshotStore,
        stdout: FileHandle = .standardOutput,
        stderr: FileHandle = .standardError
    ) throws -> Int32 {
        if command.isEmpty {
            try store.capture(payload)
            return 0
        }

        // A capture error must not change an existing status line's output or exit status.
        try? store.capture(payload)
        guard let executable = command.first, executable.hasPrefix("/") else {
            throw CommandError.absolutePathRequired
        }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = Array(command.dropFirst())
        process.standardInput = pipe
        process.standardOutput = stdout
        process.standardError = stderr
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
        // Some status lines do not read stdin and may close it before the entire write.
        try? pipe.fileHandleForWriting.write(contentsOf: payload)
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationReason == .uncaughtSignal
            ? 128 + process.terminationStatus : process.terminationStatus
    }

    private enum CommandError: Error {
        case absolutePathRequired
    }
}
