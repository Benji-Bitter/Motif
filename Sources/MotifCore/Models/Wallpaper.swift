import Foundation
import CoreMedia

/// A saved live-wallpaper design referencing a locally stored source video.
public struct WallpaperDesign: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// File name of the stored source video inside the library files directory.
    public var sourceFileName: String
    public var edit: VideoEditParameters

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        sourceFileName: String,
        edit: VideoEditParameters = .default
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sourceFileName = sourceFileName
        self.edit = edit
    }
}

/// Edit state for the wallpaper pipeline. Codable for persistence; the render
/// is deterministic for a given (video, parameters) pair.
public struct VideoEditParameters: Codable, Equatable, Sendable {
    /// Seconds from the start of the source video.
    public var trimStart: Double
    /// Seconds from the start of the source video. Must exceed `trimStart`.
    public var trimEnd: Double
    /// Seconds (source timeline) used as the Live Photo still frame.
    public var stillTime: Double
    /// Multiplier applied on top of cover-fit scale.
    public var zoom: Double
    /// Horizontal pan, fraction of output width (-1...1).
    public var offsetX: Double
    /// Vertical pan, fraction of output height (-1...1).
    public var offsetY: Double
    /// Playback speed multiplier (0.5...2.0).
    public var speed: Double
    /// Remove the audio track.
    public var muted: Bool
    /// Identifier of the target `DisplayPreset`.
    public var presetID: String

    public init(
        trimStart: Double = 0,
        trimEnd: Double = 3,
        stillTime: Double = 0,
        zoom: Double = 1,
        offsetX: Double = 0,
        offsetY: Double = 0,
        speed: Double = 1,
        muted: Bool = true,
        presetID: String = DisplayPreset.iPhone14Plus.id
    ) {
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.stillTime = stillTime
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.speed = speed
        self.muted = muted
        self.presetID = presetID
    }

    public static let `default` = VideoEditParameters()

    /// Trimmed duration in source seconds.
    public var trimmedDuration: Double { max(0, trimEnd - trimStart) }
}

/// iPhone display geometry used to pick wallpaper output size and preview
/// proportions. Pixel sizes are native render resolutions.
public struct DisplayPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Point height used to proportion the preview's clock/safe areas.
    public var pointHeight: Int
    /// Product types that map to this preset (e.g. "iPhone14,8").
    public var productTypes: [String]

    public var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    public var aspectRatio: Double { Double(pixelWidth) / Double(pixelHeight) }

    public init(id: String, name: String, pixelWidth: Int, pixelHeight: Int, pointHeight: Int, productTypes: [String]) {
        self.id = id
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointHeight = pointHeight
        self.productTypes = productTypes
    }

    // MARK: Catalogue

    public static let iPhone14Plus = DisplayPreset(
        id: "iphone-14-plus", name: "iPhone 14 Plus",
        pixelWidth: 1284, pixelHeight: 2778, pointHeight: 926,
        productTypes: ["iPhone14,8"])

    public static let iPhone14Pro = DisplayPreset(
        id: "iphone-14-pro", name: "iPhone 14 Pro",
        pixelWidth: 1179, pixelHeight: 2556, pointHeight: 852,
        productTypes: ["iPhone15,2"])

    public static let iPhone14ProMax = DisplayPreset(
        id: "iphone-14-pro-max", name: "iPhone 14 Pro Max",
        pixelWidth: 1290, pixelHeight: 2796, pointHeight: 932,
        productTypes: ["iPhone15,3"])

    public static let iPhone15 = DisplayPreset(
        id: "iphone-15", name: "iPhone 15 / 16",
        pixelWidth: 1179, pixelHeight: 2556, pointHeight: 852,
        productTypes: ["iPhone15,4", "iPhone17,3"])

    public static let iPhone15Plus = DisplayPreset(
        id: "iphone-15-plus", name: "iPhone 15 Plus / 16 Plus",
        pixelWidth: 1290, pixelHeight: 2796, pointHeight: 932,
        productTypes: ["iPhone15,5", "iPhone17,4"])

    public static let iPhone16Pro = DisplayPreset(
        id: "iphone-16-pro", name: "iPhone 16 Pro",
        pixelWidth: 1206, pixelHeight: 2622, pointHeight: 874,
        productTypes: ["iPhone17,1"])

    public static let iPhone16ProMax = DisplayPreset(
        id: "iphone-16-pro-max", name: "iPhone 16 Pro Max",
        pixelWidth: 1320, pixelHeight: 2868, pointHeight: 956,
        productTypes: ["iPhone17,2"])

    public static let iPhone13Mini = DisplayPreset(
        id: "iphone-13-mini", name: "iPhone 12/13 mini",
        pixelWidth: 1080, pixelHeight: 2340, pointHeight: 812,
        productTypes: ["iPhone13,1", "iPhone14,4"])

    public static let iPhoneSE = DisplayPreset(
        id: "iphone-se", name: "iPhone SE / 8",
        pixelWidth: 750, pixelHeight: 1334, pointHeight: 667,
        productTypes: ["iPhone12,8", "iPhone14,6"])

    public static let all: [DisplayPreset] = [
        .iPhone16ProMax, .iPhone16Pro, .iPhone15Plus, .iPhone15,
        .iPhone14ProMax, .iPhone14Pro, .iPhone14Plus,
        .iPhone13Mini, .iPhoneSE
    ]

    public static func preset(forProductType productType: String) -> DisplayPreset? {
        all.first { $0.productTypes.contains(productType) }
    }

    public static func preset(withID id: String) -> DisplayPreset {
        all.first { $0.id == id } ?? .iPhone14Plus
    }
}
