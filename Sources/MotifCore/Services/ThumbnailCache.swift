import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import os

/// Two-level thumbnail cache: in-memory NSCache + persisted JPEGs in the
/// library's Thumbnails directory. Generation happens off the main thread.
public final class ThumbnailCache: @unchecked Sendable {
    private let memory = NSCache<NSString, CGImage>()
    private let directory: URL
    private let processor = ImageProcessor()
    private let inFlight = OSAllocatedUnfairLock(initialState: [UUID: Task<CGImage?, Never>]())

    public init(directory: URL) {
        self.directory = directory
        memory.countLimit = 200
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns a thumbnail for the asset, generating + persisting one if needed.
    /// `sourceURL` should be the *rendered* artwork file or original media.
    public func thumbnail(assetID: UUID, sourceURL: URL, maxPixel: Int = 256) async -> CGImage? {
        let key = assetID.uuidString as NSString
        if let cached = memory.object(forKey: key) { return cached }

        let task = inFlight.withLock { table -> Task<CGImage?, Never> in
            if let existing = table[assetID] { return existing }
            let task = Task.detached(priority: .utility) { [self] in
                await self.generate(assetID: assetID, sourceURL: sourceURL, maxPixel: maxPixel)
            }
            table[assetID] = task
            return task
        }
        let result = await task.value
        inFlight.withLock { _ = $0.removeValue(forKey: assetID) }
        return result
    }

    private func generate(assetID: UUID, sourceURL: URL, maxPixel: Int) async -> CGImage? {
        let key = assetID.uuidString as NSString
        let diskURL = directory.appendingPathComponent("\(assetID.uuidString).jpg")

        if let image = processor.thumbnail(of: diskURL, maxPixelSize: maxPixel) {
            memory.setObject(image, forKey: key)
            return image
        }

        let ext = sourceURL.pathExtension.lowercased()
        let image: CGImage?
        if ["mov", "mp4", "m4v", "qt"].contains(ext) {
            // ImageIO can't read videos — grab a poster frame instead.
            image = await videoPosterFrame(url: sourceURL, maxPixel: maxPixel)
        } else {
            image = processor.thumbnail(of: sourceURL, maxPixelSize: maxPixel)
        }
        guard let image else { return nil }
        memory.setObject(image, forKey: key)
        persist(image, to: diskURL)
        return image
    }

    private func videoPosterFrame(url: URL, maxPixel: Int) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        return try? await generator.image(at: .zero).image
    }

    /// Stores an externally produced thumbnail (e.g. a rendered card preview).
    public func storeThumbnail(_ image: CGImage, assetID: UUID) {
        memory.setObject(image, forKey: assetID.uuidString as NSString)
        let url = directory.appendingPathComponent("\(assetID.uuidString).jpg")
        persist(image, to: url)
    }

    public func invalidate(assetID: UUID) {
        memory.removeObject(forKey: assetID.uuidString as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(assetID.uuidString).jpg"))
    }

    private func persist(_ image: CGImage, to url: URL) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.8
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        try? AtomicFile.write(data as Data, to: url)
    }
}
