import AVFoundation
import CoreImage
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

public enum LivePhotoError: Error, Equatable, Sendable {
    case stillWriteFailed
    case metadataInjectionFailed(String)
    case validationFailed(String)
}

/// The exported Live Photo asset pair. Both files carry the same pairing
/// identifier so Photos can recognize them as a Live Photo.
public struct LivePhotoPair: Sendable, Equatable {
    public var stillURL: URL
    public var videoURL: URL
    public var assetIdentifier: String
}

/// Result of checking a generated pair. A structurally valid pair is *not*
/// proof of animated lock-screen playback — that depends on the iOS version
/// and how the photo is set as wallpaper (see COMPATIBILITY.md).
public struct LivePhotoValidation: Sendable, Equatable {
    public var stillHasIdentifier: Bool
    public var videoHasIdentifier: Bool
    public var identifiersMatch: Bool
    public var hasTimedMetadataTrack: Bool
    public var videoDurationSeconds: Double

    /// The pair is structurally consistent and will import into Photos as a
    /// Live Photo. Lock-screen animation eligibility is a separate question.
    public var isStructurallyValid: Bool {
        stillHasIdentifier && videoHasIdentifier && identifiersMatch
            && hasTimedMetadataTrack && videoDurationSeconds > 0
    }
}

/// Converts an edited video into a Live Photo asset pair:
///
///   Still.jpg  — JPEG with the pairing UUID in the Apple maker note (tag 17)
///   Video.mov  — H.264 QuickTime movie carrying
///                `com.apple.quicktime.content.identifier` = same UUID plus a
///                timed `com.apple.quicktime.still-image-time` metadata track.
///
/// The video is rewritten through a pass-through reader/writer so no quality
/// is lost during metadata injection.
public struct LivePhotoGenerator: Sendable {
    private let videoProcessor: VideoProcessor

    public init(videoProcessor: VideoProcessor = VideoProcessor()) {
        self.videoProcessor = videoProcessor
    }

    public func generate(
        source: URL,
        params: VideoEditParameters,
        quality: ExportQuality = .high,
        outputDirectory: URL,
        assetIdentifier: UUID = UUID(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> LivePhotoPair {
        let identifier = assetIdentifier.uuidString
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: source)
        let edited = try await videoProcessor.makeEditedComposition(asset: asset, params: params)

        // 1. Still image with pairing metadata.
        let stillImage = try await videoProcessor.renderedStill(from: edited)
        let stillURL = outputDirectory.appendingPathComponent("Still.jpg")
        try writeStillJPEG(stillImage, assetIdentifier: identifier, to: stillURL)
        progress?(0.1)

        // 2. Export the edited video.
        let tempVideo = outputDirectory.appendingPathComponent(".tmp-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: tempVideo) }
        try await videoProcessor.export(edited: edited, to: tempVideo, quality: quality) { p in
            progress?(0.1 + 0.8 * p)
        }

        // 3. Rewrite with Live Photo pairing metadata (no re-encode).
        let videoURL = outputDirectory.appendingPathComponent("Video.mov")
        try await injectPairingMetadata(
            source: tempVideo, destination: videoURL,
            assetIdentifier: identifier, stillOutputTime: edited.stillOutputTime)
        progress?(1.0)

        return LivePhotoPair(stillURL: stillURL, videoURL: videoURL, assetIdentifier: identifier)
    }

    // MARK: - Still image metadata

    private func writeStillJPEG(_ image: CGImage, assetIdentifier: String, to url: URL) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LivePhotoError.stillWriteFailed
        }
        // Apple maker note tag 17 carries the Live Photo asset identifier.
        // This goes through the destination *properties* dictionary — the
        // CGImageMetadata route does not serialise MakerApple into JPEG.
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyMakerAppleDictionary: ["17": assetIdentifier],
            kCGImageDestinationLossyCompressionQuality: 0.92
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoError.stillWriteFailed
        }
        try AtomicFile.write(data as Data, to: url)
    }

    // MARK: - Video metadata injection

    private func injectPairingMetadata(
        source: URL, destination: URL,
        assetIdentifier: String, stillOutputTime: Double
    ) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw LivePhotoError.metadataInjectionFailed("reader")
        }
        try? FileManager.default.removeItem(at: destination)
        guard let writer = try? AVAssetWriter(outputURL: destination, fileType: .mov) else {
            throw LivePhotoError.metadataInjectionFailed("writer")
        }

        // Asset-level pairing identifier.
        let identifierItem = AVMutableMetadataItem()
        identifierItem.key = "com.apple.quicktime.content.identifier" as NSString
        identifierItem.keySpace = .quickTimeMetadata
        identifierItem.value = assetIdentifier as NSString
        writer.metadata = [identifierItem]

        // Video passthrough.
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw LivePhotoError.metadataInjectionFailed("no video track")
        }
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let videoFormats = try await videoTrack.load(.formatDescriptions)
        guard let videoFormat = videoFormats.first else {
            throw LivePhotoError.metadataInjectionFailed("video format")
        }
        let videoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: nil,
            sourceFormatHint: videoFormat)
        reader.add(videoOutput)
        writer.add(videoInput)

        // Audio passthrough, when present.
        var audioPair: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioFormats = try await audioTrack.load(.formatDescriptions)
            if let audioFormat = audioFormats.first {
                let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
                let audioInput = AVAssetWriterInput(
                    mediaType: .audio, outputSettings: nil,
                    sourceFormatHint: audioFormat)
                reader.add(audioOutput)
                writer.add(audioInput)
                audioPair = (audioOutput, audioInput)
            }
        }

        // Timed metadata track: com.apple.quicktime.still-image-time.
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8 as String
        ]
        var metadataFormat: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: nil,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &metadataFormat)
        guard let metadataFormat else {
            throw LivePhotoError.metadataInjectionFailed("metadata format description")
        }
        let metadataInput = AVAssetWriterInput(
            mediaType: .metadata, outputSettings: nil, sourceFormatHint: metadataFormat)
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        writer.add(metadataInput)

        guard reader.startReading(), writer.startWriting() else {
            throw LivePhotoError.metadataInjectionFailed(
                writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "start")
        }
        writer.startSession(atSourceTime: .zero)

        // Still-image-time marker spans the whole clip; value -1 (SInt8).
        let stillItem = AVMutableMetadataItem()
        stillItem.key = "com.apple.quicktime.still-image-time" as NSString
        stillItem.keySpace = .quickTimeMetadata
        stillItem.value = NSNumber(value: -1 as Int8)
        stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
        let group = AVTimedMetadataGroup(
            items: [stillItem],
            timeRange: CMTimeRange(
                start: CMTime(seconds: stillOutputTime, preferredTimescale: 600),
                duration: duration))
        metadataAdaptor.append(group)

        // Copy compressed samples through.
        try copySamples(output: videoOutput, input: videoInput)
        if let audioPair {
            try copySamples(output: audioPair.0, input: audioPair.1)
        }
        metadataInput.markAsFinished()

        await writer.finishWriting()
        if writer.status != .completed {
            throw LivePhotoError.metadataInjectionFailed(
                writer.error?.localizedDescription ?? "finishWriting")
        }
    }

    private func copySamples(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) throws {
        while let sample = output.copyNextSampleBuffer() {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                attempts += 1
                if attempts > 600 {
                    throw LivePhotoError.metadataInjectionFailed("writer input stalled")
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            input.append(sample)
        }
        input.markAsFinished()
    }

    // MARK: - Validation

    /// Checks that a pair is structurally consistent: the still carries the
    /// identifier, the video carries the same identifier, and the timed
    /// still-image-time track exists.
    public func validate(_ pair: LivePhotoPair) async -> LivePhotoValidation {
        var result = LivePhotoValidation(
            stillHasIdentifier: false, videoHasIdentifier: false,
            identifiersMatch: false, hasTimedMetadataTrack: false,
            videoDurationSeconds: 0)

        if let source = CGImageSourceCreateWithURL(pair.stillURL as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any],
           let id = maker["17"] as? String {
            result.stillHasIdentifier = (id == pair.assetIdentifier)
        }

        let asset = AVURLAsset(url: pair.videoURL)
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata where (item.key as? String) == "com.apple.quicktime.content.identifier" {
                if let value = try? await item.load(.stringValue), value == pair.assetIdentifier {
                    result.videoHasIdentifier = true
                }
            }
        }
        if let tracks = try? await asset.loadTracks(withMediaType: .metadata) {
            result.hasTimedMetadataTrack = !tracks.isEmpty
        }
        if let duration = try? await asset.load(.duration), duration.isNumeric {
            result.videoDurationSeconds = duration.seconds
        }
        result.identifiersMatch = result.stillHasIdentifier && result.videoHasIdentifier
        return result
    }
}
