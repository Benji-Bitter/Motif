import Foundation

/// Kind of customisation step the Apply workflow can attempt.
public enum OperationKind: String, Codable, Sendable {
    /// Replace Wallet card artwork on the device.
    case cardSkinInstall
    /// Produce the Live Photo pair on the Mac.
    case livePhotoExport
    /// Get the Live Photo onto the device (automatic or manual).
    case livePhotoTransfer
}

/// Lifecycle state of a single apply operation. `succeeded` is only ever set
/// after the operation actually completed and its result was checked.
public enum OperationStatus: Equatable, Sendable {
    case pending
    case checking
    /// The operation can be applied automatically.
    case supported
    /// The operation cannot be performed on this device/version.
    case unsupported(String)
    /// The path exists in principle but has not been verified.
    case notTested(String)
    case preparing
    case applying
    /// Finished and verified. May carry a human-readable result detail.
    case succeeded(String?)
    case failed(String)
    /// Motif produced everything needed; the user must finish on-device.
    case requiresManual(String)

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .unsupported, .requiresManual, .notTested:
            return true
        case .pending, .checking, .supported, .preparing, .applying:
            return false
        }
    }

    /// Short label for badges.
    public var label: String {
        switch self {
        case .pending: return "Pending"
        case .checking: return "Checking…"
        case .supported: return "Supported"
        case .unsupported: return "Unsupported"
        case .notTested: return "Not tested"
        case .preparing: return "Preparing…"
        case .applying: return "Applying…"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .requiresManual: return "Manual steps required"
        }
    }
}

/// A planned step in the apply pipeline with its current status.
public struct ApplyOperation: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: OperationKind
    public var title: String
    public var status: OperationStatus
    /// Additional context shown under the title (reasons, instructions).
    public var detail: String?

    public init(id: UUID = UUID(), kind: OperationKind, title: String, status: OperationStatus = .pending, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.status = status
        self.detail = detail
    }
}
