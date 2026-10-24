import Foundation

/// What a provider can promise for a given device.
public enum ProviderSupport: Equatable, Sendable {
    /// Verified working on this device — apply is allowed.
    case supported
    /// Can't be performed automatically; finished assets + instructions are produced.
    case requiresManual(String)
    /// Plausible but unverified — apply is blocked.
    case notTested(String)
    /// Known not to work.
    case unsupported(String)

    public var detail: String? {
        switch self {
        case .supported: return nil
        case .requiresManual(let d), .notTested(let d), .unsupported(let d): return d
        }
    }
}

/// The outcome of a provider actually running.
public enum ProviderOutcome: Equatable, Sendable {
    case applied(detail: String?)
    /// Everything needed was produced locally; user finishes on-device.
    case manualExport(directory: URL, instructions: String)
}

/// A device-modification provider for card artwork. Providers are only
/// registered when a working, tested implementation exists — which is why the
/// default registry ships none that can apply.
public protocol WalletSkinProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Experimental providers require explicit opt-in in settings.
    var isExperimental: Bool { get }
    func support(for device: DeviceInfo?) -> ProviderSupport
    func apply(design: CardDesign, renderedArtwork: URL, to device: DeviceInfo) async throws -> ProviderOutcome
}

/// Default provider: reports honestly that no verified path exists.
/// It is never able to apply — that is the point.
public struct UnverifiedWalletSkinProvider: WalletSkinProviding {
    public let id = "builtin.wallet.none"
    public let displayName = "Card artwork installation"
    public let isExperimental = false

    public init() {}

    public func support(for device: DeviceInfo?) -> ProviderSupport {
        guard let version = device.flatMap({ SystemVersion($0.iosVersion) }) else {
            return .unsupported("No device connected. Card artwork installation requires a connected iPhone and a verified method, which does not currently exist for any iOS version.")
        }
        if version >= SystemVersion(major: 15), version < SystemVersion(major: 16, minor: 2) {
            return .notTested("iOS 15.0–16.1.2 had community exploit-based artwork tools. Motif does not implement exploit-based providers. Export the artwork instead.")
        }
        return .unsupported("No verified jailbreak-free method exists to replace card artwork on iOS \(version). Export the artwork instead.")
    }

    public func apply(design: CardDesign, renderedArtwork: URL, to device: DeviceInfo) async throws -> ProviderOutcome {
        throw DeviceError.operationUnsupported("Card artwork installation is not implemented for any iOS version in this build.")
    }
}

/// A provider that can move finished assets onto a device.
public protocol LivePhotoTransferProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    func support(for device: DeviceInfo?) -> ProviderSupport
    func apply(pair: LivePhotoPair, to device: DeviceInfo?, outputDirectory: URL) async throws -> ProviderOutcome
}

/// The honest transfer path: produce the pair plus human instructions.
/// Writing into an iPhone's photo library from a Mac is not something a
/// non-jailbroken device supports directly, so this provider produces
/// everything needed for AirDrop/iCloud/Finder import instead.
public struct ManualInstallTransferProvider: LivePhotoTransferProviding {
    public let id = "builtin.transfer.manual"
    public let displayName = "Wallpaper transfer"

    public init() {}

    public func support(for device: DeviceInfo?) -> ProviderSupport {
        .requiresManual(
            """
            No supported interface exists for a Mac app to write into the iOS photo \
            library or set the lock screen directly. The Live Photo pair is exported; \
            import it via AirDrop, iCloud Photos, or Finder file sharing, then choose \
            it under Settings → Wallpaper (or Photos → Share → Use as Wallpaper).
            """)
    }

    public func apply(pair: LivePhotoPair, to device: DeviceInfo?, outputDirectory: URL) async throws -> ProviderOutcome {
        let instructions = """
            Motif Live Photo — manual install
            =================================

            Files in this folder:
              • Still.jpg  — the paired still image
              • Video.mov  — the paired Live Photo video

            To get the Live Photo onto your iPhone:

              1. AirDrop BOTH files to your iPhone, or
                 place both files into iCloud Photos / a shared location the
                 iPhone can reach, then save them to Photos.
              2. On the iPhone, open Photos and find the imported Live Photo.
              3. Share → Use as Wallpaper, then choose Lock Screen.
                 (iOS 17+ animates Live Photos on the lock screen.)

            Motif cannot verify on-device playback — check that the wallpaper
            animates when you wake the phone. If it doesn't, your iOS version
            may not support custom Live Photo wallpapers.

            Asset identifier: \(pair.assetIdentifier)
            """
        let file = outputDirectory.appendingPathComponent("INSTALLATION.txt")
        try AtomicFile.write(Data(instructions.utf8), to: file)
        return .manualExport(directory: outputDirectory, instructions: instructions)
    }
}
