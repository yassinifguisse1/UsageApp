import Foundation

public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Accepts "1.2.3" or "v1.2.3". Prerelease or build suffixes are rejected.
    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? string.dropFirst() : Substring(string)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2],
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct AvailableRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let url: URL
}

public enum UpdateCheck {
    public static let repository = "yassinifguisse1/UsageApp"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Parses a GitHub `releases/latest` response. Returns nil unless it is newer than `current`.
    public static func newerRelease(in data: Data, than current: String) -> AvailableRelease? {
        guard let current = ReleaseVersion(current),
              let object = try? ProviderJSON.object(from: data),
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              let version = (object["tag_name"] as? String).flatMap(ReleaseVersion.init),
              version > current,
              let link = object["html_url"] as? String, let url = URL(string: link),
              // Only ever open this project's release pages.
              url.scheme == "https", url.host() == "github.com",
              url.path().hasPrefix("/\(repository)/releases/") else { return nil }
        return AvailableRelease(version: version, url: url)
    }
}
