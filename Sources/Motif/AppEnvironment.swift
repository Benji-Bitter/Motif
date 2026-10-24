import SwiftUI
import AVFoundation
import ImageIO
import MotifCore

/// Sidebar destinations.
enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case wallet = "Wallet Studio"
    case wallpaper = "Wallpaper Studio"
    case library = "Library"
    case devices = "Devices"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "house"
        case .wallet: return "creditcard"
        case .wallpaper: return "iphone.gen3"
        case .library: return "square.grid.2x2"
        case .devices: return "cable.connector"
        case .settings: return "gearshape"
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Application-wide dependency container + navigation state.
@MainActor
final class AppEnvironment: ObservableObject {
    let store: LibraryStore
    let thumbnails: ThumbnailCache
    let deviceManager: DeviceManager
    let applyEngine: ApplyEngine
    let videoProcessor = VideoProcessor()
    let livePhotoGenerator = LivePhotoGenerator()
    let imageProcessor = ImageProcessor()

    @Published var selection: SidebarSection = .overview
    @Published var entries: [LibraryEntry] = []
    @Published var collections: [DesignCollection] = []
    @Published var recentImports: [RecentImport] = []
    @Published var showingApply = false
    @Published var alert: AlertContent?
    /// Currently open card design (set by Wallet Studio) — feeds Apply.
    @Published var activeCard: CardDesign?
    /// Currently open wallpaper design (set by Wallpaper Studio).
    @Published var activeWallpaper: WallpaperDesign?
    @Published var useSimulatedDevices = false {
        didSet { deviceManager.useSimulatedDevices = useSimulatedDevices }
    }

    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    struct AlertContent: Identifiable {
        var id = UUID()
        var title: String
        var message: String
    }

    init() throws {
        let store = try LibraryStore.defaultStore()
        self.store = store
        self.thumbnails = ThumbnailCache(directory: store.paths.thumbnails)
        self.deviceManager = DeviceManager()
        self.applyEngine = ApplyEngine()
        self.appearance = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "system") ?? .system
    }

    func start() async {
        deviceManager.startObserving()
        try? await ExampleAssets.installIfNeeded(into: store)
        await reloadLibrary()
    }

    func reloadLibrary() async {
        entries = (try? await store.entries()) ?? []
        collections = (try? await store.collections()) ?? []
        recentImports = (try? await store.recentImports()) ?? []
    }

    // MARK: - Convenience lookups

    func artworkURL(for design: CardDesign) -> URL {
        store.mediaURL(fileName: design.artworkFileName)
    }

    func videoURL(for design: WallpaperDesign) -> URL {
        store.mediaURL(fileName: design.sourceFileName)
    }

    func cardDesigns() -> [CardDesign] {
        entries.filter { $0.kind == .card }.compactMap(\.cardDesign)
    }

    func wallpaperDesigns() -> [WallpaperDesign] {
        entries.filter { $0.kind == .wallpaper }.compactMap(\.wallpaperDesign)
    }

    func entry(for id: UUID) -> LibraryEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - Imports

    /// Imports artwork, validates it, and creates a new card design.
    @discardableResult
    func importArtwork(from url: URL) async -> CardDesign? {
        do {
            _ = try ImportValidator.validateImageFile(url)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let fileName = try await store.storeMedia(from: url, kind: .card)
            let design = CardDesign(title: url.deletingPathExtension().lastPathComponent,
                                    artworkFileName: fileName)
            try await store.saveCardDesign(design)
            await reloadLibrary()
            return design
        } catch {
            alert = AlertContent(title: "Couldn't import artwork", message: error.localizedDescription)
            return nil
        }
    }

    /// Imports a video and creates a new wallpaper design.
    @discardableResult
    func importVideo(from url: URL) async -> WallpaperDesign? {
        do {
            let info = try await videoProcessor.inspect(url)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let fileName = try await store.storeMedia(from: url, kind: .wallpaper)
            var edit = VideoEditParameters.default
            edit.trimEnd = min(3, info.duration)
            // Prefer the connected device's preset when one is known.
            if let productType = deviceManager.selectedDevice?.productType,
               let preset = DisplayPreset.preset(forProductType: productType) {
                edit.presetID = preset.id
            }
            let design = WallpaperDesign(
                title: url.deletingPathExtension().lastPathComponent,
                sourceFileName: fileName, edit: edit)
            try await store.saveWallpaperDesign(design)
            await reloadLibrary()
            return design
        } catch {
            alert = AlertContent(title: "Couldn't import video", message: error.localizedDescription)
            return nil
        }
    }

    /// Imports an existing Live Photo pair (still + video) and validates that
    /// the pairing identifiers actually match before calling it a Live Photo.
    @discardableResult
    func importLivePhotoPair(still: URL, video: URL) async -> WallpaperDesign? {
        do {
            _ = try ImportValidator.validateImageFile(still)
            _ = try ImportValidator.validateVideoFile(video)
            let stillID = stillAssetIdentifier(still)
            let videoID = await videoAssetIdentifier(video)
            guard stillID != nil, stillID == videoID else {
                alert = AlertContent(
                    title: "Not a recognised Live Photo pair",
                    message: "The still image and video don't carry matching pairing identifiers, so Photos won't treat them as one Live Photo.")
                return nil
            }
            let accessing = video.startAccessingSecurityScopedResource()
            defer { if accessing { video.stopAccessingSecurityScopedResource() } }
            let info = try await videoProcessor.inspect(video)
            let fileName = try await store.storeMedia(from: video, kind: .wallpaper)
            var edit = VideoEditParameters.default
            edit.trimEnd = info.duration
            let design = WallpaperDesign(title: "Live Photo — \(stillID!.prefix(8))",
                                       sourceFileName: fileName, edit: edit)
            try await store.saveWallpaperDesign(design)
            await reloadLibrary()
            return design
        } catch {
            alert = AlertContent(title: "Couldn't import Live Photo", message: error.localizedDescription)
            return nil
        }
    }

    private func stillAssetIdentifier(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let maker = props[kCGImagePropertyMakerAppleDictionary] as? [String: Any],
              let id = maker["17"] as? String else { return nil }
        return id
    }

    private func videoAssetIdentifier(_ url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        for item in metadata where (item.key as? String) == "com.apple.quicktime.content.identifier" {
            if let value = try? await item.load(.stringValue) { return value }
        }
        return nil
    }

    /// The current apply context assembled from the studio selections.
    func applyContext(card: CardDesign?, wallpaper: WallpaperDesign?) -> ApplyContext {
        ApplyContext(
            device: deviceManager.selectedDevice,
            cardDesign: card,
            cardArtworkSource: card.map { artworkURL(for: $0) },
            wallpaperDesign: wallpaper,
            videoSource: wallpaper.map { videoURL(for: $0) },
            outputDirectory: store.paths.exports,
            exportQuality: .high)
    }
}
