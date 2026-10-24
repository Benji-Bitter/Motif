import Foundation

/// A customisation surface we can report on.
public enum Feature: String, Codable, Sendable, CaseIterable {
    /// Replace card artwork inside the Wallet stack on-device.
    case cardArtworkReplacement
    /// Produce a Live Photo pair on the Mac.
    case livePhotoExport
    /// Whether iOS itself can animate a custom Live Photo on the lock screen.
    case livePhotoLockScreenPlayback
    /// Move the finished Live Photo onto the phone.
    case livePhotoTransfer
    /// Host-side device detection.
    case deviceDetection
}

public enum AvailabilityStatus: Equatable, Sendable {
    case supported
    case requiresManual
    case notTested
    case unsupported

    public var label: String {
        switch self {
        case .supported: return "Supported"
        case .requiresManual: return "Manual install"
        case .notTested: return "Not verified"
        case .unsupported: return "Unsupported"
        }
    }
}

public struct FeatureAvailability: Equatable, Sendable, Identifiable {
    public var id: Feature { feature }
    public var feature: Feature
    public var status: AvailabilityStatus
    /// The honest explanation shown next to the status — no invented capability.
    public var note: String
}

/// Single source of truth for "what works on this iOS version". All entries
/// are deliberately conservative: where we haven't verified behaviour we say
/// `notTested`, and where no non-jailbreak method exists we say `unsupported`.
public enum CapabilityRegistry {

    public static func availability(for device: DeviceInfo?) -> [FeatureAvailability] {
        let version = device.flatMap { SystemVersion($0.iosVersion) }
        return Feature.allCases.map { availability(of: $0, iOS: version, device: device) }
    }

    public static func availability(
        of feature: Feature,
        iOS version: SystemVersion?,
        device: DeviceInfo? = nil
    ) -> FeatureAvailability {
        switch feature {
        case .cardArtworkReplacement:
            // There is no public/verified jailbreak-free mechanism to replace
            // Wallet card artwork. CVE-2022-46689-era community tools existed
            // for iOS 15.0–16.1.2; Motif does not ship exploit-based providers,
            // so those versions are "not verified" rather than "supported".
            if let version, version >= SystemVersion(major: 15),
               version < SystemVersion(major: 16, minor: 2) {
                return FeatureAvailability(
                    feature: feature, status: .notTested,
                    note: "Community exploit-based tools exist for iOS 15.0–16.1.2; Motif does not implement them. Artwork can still be exported.")
            }
            return FeatureAvailability(
                feature: feature, status: .unsupported,
                note: "No verified jailbreak-free method exists to replace card artwork on this iOS version. Export your design instead.")

        case .livePhotoExport:
            return FeatureAvailability(
                feature: feature, status: .supported,
                note: "Live Photo pairs are generated locally on this Mac.")

        case .livePhotoLockScreenPlayback:
            guard let version else {
                return FeatureAvailability(
                    feature: feature, status: .notTested,
                    note: "Connect a device to check lock-screen playback support.")
            }
            if version >= SystemVersion(major: 17) {
                return FeatureAvailability(
                    feature: feature, status: .supported,
                    note: "iOS 17+ supports Live Photo wallpapers (set via Photos → Share → Set as Wallpaper, or Settings → Wallpaper). Motif must not claim the animation without on-device verification.")
            }
            if version.major == 16 {
                return FeatureAvailability(
                    feature: feature, status: .notTested,
                    note: "iOS 16 Live Photo wallpaper behaviour varies; verify on-device.")
            }
            return FeatureAvailability(
                feature: feature, status: .notTested,
                note: "Live Photos may play via long-press on this iOS version; unverified.")

        case .livePhotoTransfer:
            return FeatureAvailability(
                feature: feature, status: .requiresManual,
                note: "No supported way for a Mac app to write into iOS Photos or set the wallpaper directly. The pair is exported with import instructions (AirDrop / iCloud / Finder sync).")

        case .deviceDetection:
            if device != nil {
                return FeatureAvailability(
                    feature: feature, status: .supported,
                    note: "Device detected over USB.")
            }
            return FeatureAvailability(
                feature: feature, status: .requiresManual,
                note: "Requires libimobiledevice (`brew install libimobiledevice`) and a paired iPhone.")
        }
    }
}
