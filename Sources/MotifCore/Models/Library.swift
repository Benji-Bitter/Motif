import Foundation

/// Kind of asset stored in the local library.
public enum AssetKind: String, Codable, Sendable, CaseIterable {
    case card
    case wallpaper
}

/// A library row: stable metadata + a JSON payload containing the full design.
public struct LibraryEntry: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: AssetKind
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var isFavorite: Bool
    public var collectionID: UUID?
    public var tags: [String]
    /// JSON-encoded CardDesign or WallpaperDesign depending on `kind`.
    public var payload: Data

    public init(
        id: UUID,
        kind: AssetKind,
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        isFavorite: Bool = false,
        collectionID: UUID? = nil,
        tags: [String] = [],
        payload: Data
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isFavorite = isFavorite
        self.collectionID = collectionID
        self.tags = tags
        self.payload = payload
    }

    public var cardDesign: CardDesign? {
        kind == .card ? try? JSONDecoder().decode(CardDesign.self, from: payload) : nil
    }

    public var wallpaperDesign: WallpaperDesign? {
        kind == .wallpaper ? try? JSONDecoder().decode(WallpaperDesign.self, from: payload) : nil
    }
}

/// User-defined grouping of library assets.
public struct DesignCollection: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AssetKind?
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, kind: AssetKind? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
    }
}

/// Record of a file the user imported (for the "Recently imported" shelf).
public struct RecentImport: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var originalName: String
    public var storedFileName: String
    public var kind: AssetKind
    public var importedAt: Date

    public init(id: UUID = UUID(), originalName: String, storedFileName: String, kind: AssetKind, importedAt: Date = Date()) {
        self.id = id
        self.originalName = originalName
        self.storedFileName = storedFileName
        self.kind = kind
        self.importedAt = importedAt
    }
}

/// Wire format for sharing a single design between machines. Contains the
/// design payload plus embedded source media so designs are self-contained.
public struct DesignBundle: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var kind: AssetKind
    /// JSON-encoded CardDesign/WallpaperDesign.
    public var design: Data
    /// The source media file (artwork image or video) embedded for portability.
    public var mediaFileName: String
    public var mediaData: Data

    public init(formatVersion: Int = DesignBundle.currentFormatVersion, kind: AssetKind, design: Data, mediaFileName: String, mediaData: Data) {
        self.formatVersion = formatVersion
        self.kind = kind
        self.design = design
        self.mediaFileName = mediaFileName
        self.mediaData = mediaData
    }
}

/// Draft catalogue record describing a community-provided asset. A remote
/// catalogue is intentionally not shipped in v0.1; this schema is the
/// documented contract for a future implementation (see CATALOGUE.md).
public struct CatalogueRecord: Codable, Equatable, Sendable {
    public var assetID: String
    public var title: String
    public var creator: String
    public var category: String
    public var tags: [String]
    public var previewURL: URL
    public var sourceURL: URL
    public var licence: String
    public var fileChecksumSHA256: String
    public var compatibleExportFormats: [String]

    public init(assetID: String, title: String, creator: String, category: String,
                tags: [String], previewURL: URL, sourceURL: URL, licence: String,
                fileChecksumSHA256: String, compatibleExportFormats: [String]) {
        self.assetID = assetID
        self.title = title
        self.creator = creator
        self.category = category
        self.tags = tags
        self.previewURL = previewURL
        self.sourceURL = sourceURL
        self.licence = licence
        self.fileChecksumSHA256 = fileChecksumSHA256
        self.compatibleExportFormats = compatibleExportFormats
    }
}
