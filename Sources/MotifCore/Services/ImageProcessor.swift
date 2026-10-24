import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageProcessingError: Error, Equatable, Sendable {
    case decodeFailed(String)
    case renderFailed
    case writeFailed(String)
}

/// Core Image based image pipeline shared by the card editor and the
/// wallpaper still-frame path. Stateless and safe to call from any context.
public struct ImageProcessor: Sendable {
    private let context: CIContext

    public init() {
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])
    }

    // MARK: - Loading

    /// Loads an image honouring its EXIF orientation.
    public func loadCIImage(from url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              image.extent.width > 0, image.extent.height > 0 else {
            throw ImageProcessingError.decodeFailed(url.lastPathComponent)
        }
        return image
    }

    public func loadCGImage(from url: URL) throws -> CGImage {
        let ci = try loadCIImage(from: url)
        guard let cg = context.createCGImage(ci, from: ci.extent) else {
            throw ImageProcessingError.renderFailed
        }
        return cg
    }

    // MARK: - Adjustments

    /// Applies brightness / contrast / saturation / sharpness adjustments.
    public func filtered(_ image: CIImage, params: CardEditParameters) -> CIImage {
        var output = image

        if params.brightness != 0 || params.contrast != 1 || params.saturation != 1 {
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.brightness = Float(params.brightness * 0.3)   // scale to useful range
            controls.contrast = Float(params.contrast)
            controls.saturation = Float(params.saturation)
            if let result = controls.outputImage { output = result }
        }

        if params.sharpness > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = output
            sharpen.sharpness = Float(params.sharpness)
            sharpen.radius = 2.5
            if let result = sharpen.outputImage { output = result }
        }

        return output
    }

    // MARK: - Rendering

    public func render(_ image: CIImage, extent: CGRect) throws -> CGImage {
        guard let cg = context.createCGImage(image, from: extent) else {
            throw ImageProcessingError.renderFailed
        }
        return cg
    }

    // MARK: - Writing

    public func pngData(of image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageProcessingError.writeFailed("destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.writeFailed("finalize")
        }
        return data as Data
    }

    public func writePNG(_ image: CGImage, to url: URL) throws {
        try AtomicFile.write(try pngData(of: image), to: url)
    }

    // MARK: - Thumbnails

    /// Fast thumbnail via ImageIO — does not decode the full resolution image.
    public func thumbnail(of url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public func thumbnail(of image: CGImage, maxPixelSize: Int) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination),
              let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
