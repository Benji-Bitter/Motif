import Foundation

/// How a device is physically connected.
public enum DeviceTransport: String, Codable, Sendable {
    case usb
    case network
}

/// Pairing/trust state as reported by the host pairing records.
public enum TrustState: String, Codable, Sendable {
    /// The device is paired and trusts this computer.
    case trusted
    /// The device is connected but has not trusted this computer.
    case untrusted
    /// The device appears locked — it must be unlocked before pairing works.
    case locked
    /// Trust state could not be determined.
    case unknown
}

/// High-level connection state surfaced to the UI.
public enum DeviceConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    /// Connected over USB but the iPhone must be unlocked.
    case needsUnlock
    /// Connected but the user has not trusted this computer on the iPhone.
    case needsTrust
    /// Paired and accessible.
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }
}

/// Ephemeral information about a connected device. The device identifier is
/// kept only in memory for the duration of the connection and is never
/// persisted.
public struct DeviceInfo: Identifiable, Equatable, Sendable {
    /// Ephemeral identifier (UDID) used only for this session.
    public let id: String
    public var name: String
    /// e.g. "iPhone15,2".
    public var productType: String
    /// Resolved marketing name, e.g. "iPhone 14 Pro".
    public var modelName: String
    public var iosVersion: String
    public var buildVersion: String?
    public var transport: DeviceTransport
    public var trustState: TrustState
    public var connectionState: DeviceConnectionState
    /// true when this entry comes from the simulated device service used for
    /// development — the UI must label these accordingly.
    public var isSimulated: Bool

    public init(
        id: String,
        name: String,
        productType: String,
        modelName: String,
        iosVersion: String,
        buildVersion: String? = nil,
        transport: DeviceTransport = .usb,
        trustState: TrustState = .unknown,
        connectionState: DeviceConnectionState = .connecting,
        isSimulated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.productType = productType
        self.modelName = modelName
        self.iosVersion = iosVersion
        self.buildVersion = buildVersion
        self.transport = transport
        self.trustState = trustState
        self.connectionState = connectionState
        self.isSimulated = isSimulated
    }

    /// Major iOS version component, if parseable.
    public var iOSMajorVersion: Int? {
        iosVersion.split(separator: ".").first.flatMap { Int($0) }
    }
}

public enum DeviceError: Error, Equatable, Sendable {
    /// libimobiledevice command-line tools were not found on this Mac.
    case toolchainMissing
    /// The device must be unlocked before information can be read.
    case deviceLocked
    /// The computer is not trusted by the device.
    case notTrusted
    case communicationFailed(String)
    case operationUnsupported(String)
}

/// One line in the device diagnostics log.
public struct DiagnosticsEntry: Equatable, Identifiable, Sendable {
    public enum Level: String, Sendable { case info, warning, error }

    public var id: UUID = UUID()
    public var timestamp: Date
    public var level: Level
    public var message: String

    public init(level: Level, message: String, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

/// Resolves Apple product types ("iPhone15,2") to marketing names.
/// Unknown product types return the raw identifier — never a guess.
public enum DeviceModelCatalog {
    private static let table: [String: String] = [
        "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7",
        "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
        "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd gen)", "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e"
    ]

    public static func marketingName(for productType: String) -> String {
        table[productType] ?? (productType.hasPrefix("iPhone") ? "iPhone (\(productType))" : productType)
    }
}
