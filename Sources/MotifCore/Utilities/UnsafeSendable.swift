import Foundation

/// Sendable box for pre-concurrency types that we access in a serialized way
/// anyway (e.g. an AVAssetExportSession only touched by one call's closures).
/// Kept narrow and internal so it can't leak unsafety elsewhere.
struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
