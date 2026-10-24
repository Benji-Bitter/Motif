import Foundation
import CoreGraphics
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import MotifCore

enum TestHelpers {

    /// Fresh per-test library root inside the system temp directory.
    static func tempLibraryRoot(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MotifTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// Writes a solid-color CGImage with a contrasting center block, useful to
    /// verify transforms actually move content.
    static func makeTestImage(
        size: CGSize = CGSize(width: 400, height: 300),
        base: (UInt8, UInt8, UInt8) = (220, 40, 40),
        block: (UInt8, UInt8, UInt8)? = (40, 40, 220)
    ) -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: CGFloat(base.0) / 255, green: CGFloat(base.1) / 255,
                                 blue: CGFloat(base.2) / 255, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        if let block {
            ctx.setFillColor(CGColor(red: CGFloat(block.0) / 255, green: CGFloat(block.1) / 255,
                                     blue: CGFloat(block.2) / 255, alpha: 1))
            ctx.fill(CGRect(x: size.width * 0.4, y: size.height * 0.4,
                            width: size.width * 0.2, height: size.height * 0.2))
        }
        return ctx.makeImage()!
    }

    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL) throws -> URL {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        try data.write(to: url)
        return url
    }

    /// Synthesizes a small H.264 video — no bundled fixtures required.
    static func makeTestVideo(
        at url: URL,
        duration: Double = 1.0,
        fps: Int32 = 30,
        size: CGSize = CGSize(width: 320, height: 240),
        withAudio: Bool = false
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(fps))
        var frame = 0
        while input.isReadyForMoreMediaData && frame < totalFrames {
            if let pool = adaptor.pixelBufferPool,
               let buffer = makePixelBuffer(pool: pool, size: size, seed: frame) {
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            }
            frame += 1
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? VideoProcessingError.exportFailed("test video writer")
        }
    }

    private static func makePixelBuffer(pool: CVPixelBufferPool, size: CGSize, seed: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = Int(size.height)
        let width = Int(size.width)
        // ARGB gradient; shifts per frame so frames differ.
        let r = UInt8((seed * 7) % 255)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let px = row.advanced(by: x * 4)
                px[0] = UInt8(clamping: (x + seed * 3) % 255)  // A? ARGB order: a,r,g,b
                px[1] = r
                px[2] = UInt8(clamping: (y * 2 + seed) % 255)
                px[3] = UInt8(clamping: (x + y) % 255)
            }
        }
        return buffer
    }

    /// Reads a single RGBA-ish pixel from a CGImage.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let data = image.dataProvider?.data else { return nil }
        let bytes = CFDataGetBytePtr(data)
        guard let bytes else { return nil }
        let bpp = image.bitsPerPixel / 8
        let offset = y * image.bytesPerRow + x * bpp
        guard offset + 2 < CFDataGetLength(data) else { return nil }
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bpp > 3 ? bytes[offset + 3] : 255)
    }
}
