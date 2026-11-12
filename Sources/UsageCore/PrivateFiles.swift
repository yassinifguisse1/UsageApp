import Darwin
import Foundation

/// Owner-only files in UsageApp's Application Support directory.
enum PrivateFiles {
    enum Failure: Error {
        case unsafeDirectory, fileOperation
    }

    static func prepare(directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0 else { throw Failure.unsafeDirectory }
    }

    /// Writes a 0600 temporary file next to the destination and renames it into place.
    static func replace(_ destination: URL, with data: Data) throws {
        let prefix = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).")
        var template = Array((prefix.path + "XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw Failure.fileOperation }
        let temporary = String(decoding: template.dropLast().map(UInt8.init(bitPattern:)), as: UTF8.self)
        defer { _ = unlink(temporary) }

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
        guard rename(temporary, destination.path) == 0 else { throw Failure.fileOperation }
    }
}
