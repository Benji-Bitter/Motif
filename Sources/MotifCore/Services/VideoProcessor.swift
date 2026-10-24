import AVFoundation
import CoreImage
import CoreMedia

public enum VideoProcessingError: Error, Equatable, Sendable {
    case noVideoTrack
    case invalidDuration
    case exportFailed(String)
    case cancelled
    case stillFrameFailed
}

/// Summary of a validated source video.
public struct VideoInfo: Sendable, Equatable {
    public var duration: Double
    /// Upright dimensions (preferred transform applied).
    public var dimensions: CGSize
    public var hasAudio: Bool
    public var nominalFrameRate: Float
}

/// Export quality presets. Quality maps to a render-scale multiplier applied
/// to the target display preset — the always-`HighestQuality` export preset is
/// used because the resolution-locked presets would override the render size.
public enum ExportQuality: String, Sendable, CaseIterable {
    case high, medium, low

    public var displayName: String {
        switch self {
        case .high: return "High (full resolution)"
        case .medium: return "Medium (¾ resolution)"
        case .low: return "Low (½ resolution)"
        }
    }

    /// Fraction of the preset's native resolution.
    public var renderScale: Double {
        switch self {
        case .high: return 1.0
        case .medium: return 0.75
        case .low: return 0.5
        }
    }
}

/// The result of building an edited composition: everything needed to preview,
/// export, or generate a Live Photo.
public struct EditedComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    /// Duration of the edited output in seconds.
    public let outputDuration: Double
    /// Position of the Live Photo still frame on the *output* timeline.
    public let stillOutputTime: Double
}

/// Cover-fit math shared by the video pipeline and previews.
public enum CoverFraming {
    /// Transform for a `AVMutableVideoCompositionLayerInstruction`: normalizes
    /// the track's preferred transform, then cover-fits the upright content
    /// into `renderSize` honouring zoom and pan offsets.
    public static func layerTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize,
        zoom: Double,
        offsetX: Double,
        offsetY: Double
    ) -> CGAffineTransform {
        let normalized = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let normalize = preferredTransform.concatenating(
            CGAffineTransform(translationX: -normalized.minX, y: -normalized.minY))
        return normalize.concatenating(imageTransform(
            contentSize: normalized.standardized.size,
            renderSize: renderSize, zoom: zoom, offsetX: offsetX, offsetY: offsetY))
    }

    /// Transform for already-upright content at the origin into `renderSize`
    /// (cover-fit, zoom, pan). Y offsets follow the caller's coordinate space.
    public static func imageTransform(
        contentSize: CGSize,
        renderSize: CGSize,
        zoom: Double,
        offsetX: Double,
        offsetY: Double
    ) -> CGAffineTransform {
        guard contentSize.width > 0, contentSize.height > 0 else { return .identity }
        let scale = max(renderSize.width / contentSize.width,
                        renderSize.height / contentSize.height) * zoom
        let tx = (renderSize.width - contentSize.width * scale) / 2 + offsetX * renderSize.width
        let ty = (renderSize.height - contentSize.height * scale) / 2 + offsetY * renderSize.height
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}

/// All video work: validation, composition building, exporting, still frames.
/// Expensive work is async; cancellation is observed during export.
public actor VideoProcessor {

    public init() {}

    // MARK: - Inspection

    public func inspect(_ url: URL) async throws -> VideoInfo {
        _ = try ImportValidator.validateVideoFile(url)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else {
            throw VideoProcessingError.invalidDuration
        }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw VideoProcessingError.noVideoTrack }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let upright = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized.size
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        let fps = (try? await track.load(.nominalFrameRate)) ?? 30
        return VideoInfo(duration: duration.seconds, dimensions: upright,
                         hasAudio: hasAudio, nominalFrameRate: fps)
    }

    // MARK: - Composition building

    /// Builds a trimmed, speed-adjusted, cover-cropped composition.
    /// The still time is also mapped onto the output timeline.
    public func makeEditedComposition(asset: AVURLAsset, params: VideoEditParameters) async throws -> EditedComposition {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceTrack = videoTracks.first else { throw VideoProcessingError.noVideoTrack }
        let assetDuration = try await asset.load(.duration)
        guard assetDuration.isNumeric else { throw VideoProcessingError.invalidDuration }

        let trimStart = max(0, params.trimStart)
        let trimEnd = min(max(params.trimEnd, trimStart + 0.1), assetDuration.seconds)
        let range = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600))

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoProcessingError.noVideoTrack
        }
        try videoTrack.insertTimeRange(range, of: sourceTrack, at: .zero)

        if !params.muted,
           let audioSource = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(range, of: audioSource, at: .zero)
        }

        var outputDuration = range.duration.seconds
        if params.speed != 1 {
            let scaled = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / params.speed)
            composition.scaleTimeRange(
                CMTimeRange(start: .zero, duration: range.duration), toDuration: scaled)
            outputDuration = scaled.seconds
        }

        // Map the chosen still time (source timeline) onto the output timeline.
        let stillOutput = max(0, (params.stillTime - trimStart) / params.speed)

        let naturalSize = try await sourceTrack.load(.naturalSize)
        let preferred = try await sourceTrack.load(.preferredTransform)
        let preset = DisplayPreset.preset(withID: params.presetID)
        let transform = CoverFraming.layerTransform(
            naturalSize: naturalSize, preferredTransform: preferred,
            renderSize: preset.pixelSize,
            zoom: params.zoom, offsetX: params.offsetX, offsetY: params.offsetY)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: outputDuration, preferredTimescale: 600))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = preset.pixelSize
        videoComposition.instructions = [instruction]
        videoComposition.renderScale = 1.0
        if let minFrame = try? await sourceTrack.load(.minFrameDuration),
           minFrame.isNumeric, minFrame.seconds > 0 {
            videoComposition.frameDuration = minFrame
        } else {
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        }

        return EditedComposition(
            composition: composition,
            videoComposition: videoComposition,
            outputDuration: outputDuration,
            stillOutputTime: stillOutput)
    }

    // MARK: - Export

    /// Exports an edited composition. Reports progress and honours cancellation.
    public func export(
        edited: EditedComposition,
        to url: URL,
        quality: ExportQuality = .high,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let session = AVAssetExportSession(
            asset: edited.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoProcessingError.exportFailed("could not create export session")
        }
        try? FileManager.default.removeItem(at: url)
        session.outputURL = url
        session.outputFileType = .mov
        // AVAssetExportSession requires renderScale == 1.0; scale renderSize on
        // a copy instead so the shared composition stays full-resolution.
        guard let videoComposition = edited.videoComposition.mutableCopy() as? AVMutableVideoComposition else {
            throw VideoProcessingError.exportFailed("video composition copy")
        }
        if quality.renderScale != 1.0 {
            let size = videoComposition.renderSize
            let w = max(2, Int(size.width * quality.renderScale) & ~1)
            let h = max(2, Int(size.height * quality.renderScale) & ~1)
            videoComposition.renderSize = CGSize(width: w, height: h)
        }
        session.videoComposition = videoComposition

        // AVAssetExportSession predates Sendable; the box is safe because the
        // session is only touched by this call's own closures.
        let boxed = UnsafeSendable(session)

        let progressTask = Task {
            while !Task.isCancelled {
                progress?(Double(boxed.value.progress))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                boxed.value.exportAsynchronously {
                    progressTask.cancel()
                    switch boxed.value.status {
                    case .completed:
                        progress?(1.0)
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: VideoProcessingError.cancelled)
                    case .failed:
                        continuation.resume(throwing: VideoProcessingError.exportFailed(
                            boxed.value.error?.localizedDescription ?? "export failed"))
                    default:
                        continuation.resume(throwing: VideoProcessingError.exportFailed("unknown export state"))
                    }
                }
            }
        } onCancel: {
            progressTask.cancel()
            boxed.value.cancelExport()
        }
    }

    // MARK: - Still frames

    /// Renders a still frame through the composition's video composition so the
    /// Live Photo still matches the exported video framing exactly.
    public func renderedStill(from edited: EditedComposition) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: edited.composition)
        generator.appliesPreferredTrackTransform = false
        generator.videoComposition = edited.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: min(edited.stillOutputTime, edited.outputDuration - 0.05),
                          preferredTimescale: 600)
        do {
            let (image, _) = try await generator.image(at: time)
            return image
        } catch {
            throw VideoProcessingError.stillFrameFailed
        }
    }

    /// Unedited frame of the original asset — used by the "compare" preview.
    public func originalStill(from url: URL, at seconds: Double) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        do {
            let (image, _) = try await generator.image(at: time)
            return image
        } catch {
            throw VideoProcessingError.stillFrameFailed
        }
    }
}
