import Foundation

/// User-editable parameters describing how source artwork is transformed into
/// finished card artwork. A pure value type: the render is deterministic for a
/// given (image, parameters) pair.
public struct CardEditParameters: Codable, Equatable, Sendable {
    /// Multiplier applied on top of the cover-fit scale. 1.0 = fills the card.
    public var zoom: Double
    /// Horizontal pan expressed as a fraction of the canvas width (-1...1).
    public var offsetX: Double
    /// Vertical pan expressed as a fraction of the canvas height (-1...1).
    public var offsetY: Double
    /// Rotation in degrees, applied around the canvas centre.
    public var rotationDegrees: Double
    /// -1...1, 0 = unchanged.
    public var brightness: Double
    /// 0.25...4, 1 = unchanged.
    public var contrast: Double
    /// 0...3, 1 = unchanged.
    public var saturation: Double
    /// 0...2, 0 = unchanged.
    public var sharpness: Double

    public init(
        zoom: Double = 1,
        offsetX: Double = 0,
        offsetY: Double = 0,
        rotationDegrees: Double = 0,
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        sharpness: Double = 0
    ) {
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotationDegrees = rotationDegrees
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.sharpness = sharpness
    }

    public static let `default` = CardEditParameters()
}

/// A saved card artwork design. Stable `id` is used for persistence,
/// thumbnails and exports.
public struct CardDesign: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// File name of the imported source artwork inside the library files
    /// directory (not an absolute path — the library may be relocated).
    public var artworkFileName: String
    public var edit: CardEditParameters

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        artworkFileName: String,
        edit: CardEditParameters = .default
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.artworkFileName = artworkFileName
        self.edit = edit
    }
}

/// Physical geometry of an ISO 7810 ID-1 card, used for preview and export
/// aspect. Width 85.60 mm, height 53.98 mm, corner radius ~3.18 mm.
public enum CardGeometry {
    public static let aspectRatio: Double = 85.60 / 53.98
    /// Corner radius as a fraction of card height.
    public static let cornerRadiusFraction: Double = 3.18 / 53.98

    public static func cornerRadius(forHeight height: Double) -> Double {
        height * cornerRadiusFraction
    }
}

/// Named export resolutions for card artwork. 1536x969 is the de-facto
/// community preset for card-skin artwork (approx. 18 px/mm).
public struct CardExportPreset: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let width: Int
    public let height: Int
    public var pixelSize: CGSize { CGSize(width: width, height: height) }

    public static let standard = CardExportPreset(name: "Card 1536 × 969", width: 1536, height: 969)
    public static let high = CardExportPreset(name: "Card 2304 × 1454", width: 2304, height: 1454)
    public static let compact = CardExportPreset(name: "Card 856 × 540", width: 856, height: 540)

    public static let all: [CardExportPreset] = [.standard, .high, .compact]
}
