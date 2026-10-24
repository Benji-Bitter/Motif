import Foundation

/// Comparable semantic-ish version for iOS version strings like "17.5.1".
public struct SystemVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        guard let first = parts.first else { return nil }
        self.init(major: first,
                  minor: parts.count > 1 ? parts[1] : 0,
                  patch: parts.count > 2 ? parts[2] : 0)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SystemVersion, rhs: SystemVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
