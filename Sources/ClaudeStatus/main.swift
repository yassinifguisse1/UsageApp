import Darwin
import Foundation
import UsageCore

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] {
    print("Usage: usageapp-claude-status [-- /absolute/path/to/previous-status-line [arguments...]]")
    exit(0)
}
guard arguments.isEmpty || (arguments.first == "--" && arguments.count > 1) else {
    try? FileHandle.standardError.write(contentsOf: Data("Use --help for invocation details.\n".utf8))
    exit(64)
}

do {
    let payload = try FileHandle.standardInput.readToEnd() ?? Data()
    let status = try ClaudeStatusCommand.run(
        payload: payload,
        command: Array(arguments.dropFirst()),
        store: ClaudeSnapshotStore()
    )
    exit(status)
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("UsageApp could not capture usage or run the status line.\n".utf8))
    exit(1)
}
