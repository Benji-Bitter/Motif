import Foundation
import CoreImage
import CoreGraphics

/// Turns a source image + edit parameters into finished card artwork.
/// The same math drives the live preview and the PNG export, so the preview
/// is exactly what gets exported (WYSIWYG).
public enum CardArtworkRenderer {

    /// Builds the transform mapping the source image into output space:
    /// centre → rotate → cover-scale × zoom → translate to canvas centre + pan.
    public static func artworkTransform(
        imageExtent: CGRect,
        outputSize: CGSize,
        params: CardEditParameters
    ) -> CGAffineTransform {
        let coverScale = max(outputSize.width / imageExtent.width,
                             outputSize.height / imageExtent.height)
        let scale = coverScale * params.zoom
        var transform = CGAffineTransform(
            translationX: -imageExtent.midX,
            y: -imageExtent.midY)
        transform = transform.concatenating(CGAffineTransform(rotationAngle: params.rotationDegrees * .pi / 180))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(
            translationX: outputSize.width / 2 + params.offsetX * outputSize.width,
            y: outputSize.height / 2 + params.offsetY * outputSize.height))
        return transform
    }

    /// Renders the card artwork into `outputSize` and returns a CGImage
    /// exactly `outputSize` big (the viewport is clipped).
    public static func render(
        source: CIImage,
        params: CardEditParameters,
        outputSize: CGSize,
        processor: ImageProcessor
    ) throws -> CGImage {
        let filtered = processor.filtered(source, params: params)
        let transform = artworkTransform(imageExtent: source.extent, outputSize: outputSize, params: params)
        let framed = filtered.transformed(by: transform)
        return try processor.render(framed, extent: CGRect(origin: .zero, size: outputSize))
    }

    /// Renders a preview-size image (cheaper, same framing as export).
    public static func renderPreview(
        source: CIImage,
        params: CardEditParameters,
        maxPixelWidth: Double,
        processor: ImageProcessor
    ) throws -> CGImage {
        let size = CGSize(width: maxPixelWidth, height: maxPixelWidth / CardGeometry.aspectRatio)
        return try render(source: source, params: params, outputSize: size, processor: processor)
    }
}
