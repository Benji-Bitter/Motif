import SwiftUI
import AVFoundation
import ImageIO
import MotifCore

/// Editor state for one wallpaper design: source asset, live-edited player,
/// timeline thumbnails, and the Live Photo / export pipeline.
@MainActor
final class WallpaperModel: ObservableObject {
    @Published private(set) var design: WallpaperDesign
    @Published private(set) var info: VideoInfo?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var lockScreenStill: CGImage?
    @Published private(set) var originalStill: CGImage?
    @Published private(set) var timelineThumbnails: [CGImage] = []
    @Published private(set) var isProcessing = false
    @Published var exportProgress: Double?
    @Published private(set) var exportResult: ExportResult?
    @Published var compareOriginal = false

    /// Summary of a completed generation — distinguishes "valid pair" from
    /// "actually animating on a lock screen", which is never claimed here.
    struct ExportResult: Sendable {
        var pair: LivePhotoPair
        var validation: LivePhotoValidation
        var directory: URL
    }

    @Published private(set) var history: EditHistory<VideoEditParameters>
    private(set) var sourceURL: URL
    private var asset: AVURLAsset
    private var edited: EditedComposition?
    private let processor = VideoProcessor()
    private let generator = LivePhotoGenerator()
    private var rebuildTask: Task<Void, Never>?

    var edit: VideoEditParameters { history.current }

    init(design: WallpaperDesign, sourceURL: URL) {
        self.design = design
        self.sourceURL = sourceURL
        self.asset = AVURLAsset(url: sourceURL)
        self.history = EditHistory(design.edit)
        Task { await load() }
    }

    private func load() async {
        do {
            let loaded = try await processor.inspect(sourceURL)
            info = loaded
            // Keep trim bounds inside the real duration.
            var p = history.current
            p.trimStart = max(0, min(p.trimStart, loaded.duration - 0.1))
            p.trimEnd = max(p.trimStart + 0.1, min(p.trimEnd == 0 ? loaded.duration : p.trimEnd, loaded.duration))
            p.stillTime = max(p.trimStart, min(p.stillTime, p.trimEnd))
            history.push(p)
            await makeTimelineThumbnails(duration: loaded.duration)
            await rebuildComposition()
            originalStill = try? await processor.originalStill(from: sourceURL, at: p.stillTime)
        } catch {
            // Source missing/broken — handled by the view's error surface.
        }
    }

    // MARK: - Edits

    func update(_ mutate: (inout VideoEditParameters) -> Void) {
        var next = history.current
        mutate(&next)
        history.push(next)
        design.edit = next
        scheduleRebuild()
    }

    func beginStroke() { history.beginStroke() }
    func updateInPlace(_ mutate: (inout VideoEditParameters) -> Void) {
        var next = history.current
        mutate(&next)
        history.updateInPlace(next)
        design.edit = next
        scheduleRebuild()
    }
    func endStroke() { history.endStroke() }

    func undo() { if history.undo() { design.edit = history.current; scheduleRebuild() } }
    func redo() { if history.redo() { design.edit = history.current; scheduleRebuild() } }
    func reset() {
        history.reset(to: VideoEditParameters(
            trimStart: 0, trimEnd: info.map { min(3, $0.duration) } ?? 3,
            presetID: history.current.presetID))
        design.edit = history.current
        scheduleRebuild()
    }

    // MARK: - Composition + live preview

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.rebuildComposition()
        }
    }

    /// Rebuilds the edited composition and swaps the player's item so the
    /// preview plays exactly what will be exported.
    private func rebuildComposition() async {
        do {
            let comp = try await processor.makeEditedComposition(asset: asset, params: history.current)
            edited = comp
            let item = AVPlayerItem(asset: comp.composition)
            item.videoComposition = comp.videoComposition
            if let player {
                player.replaceCurrentItem(with: item)
            } else {
                player = AVPlayer(playerItem: item)
            }
            player?.isMuted = true   // preview is always muted; mute flag affects export
            // Refresh the lock-screen still through the same pipeline.
            lockScreenStill = try? await processor.renderedStill(from: comp)
            originalStill = try? await processor.originalStill(
                from: sourceURL, at: history.current.stillTime)
        } catch {
            // Composition failure surfaces in the view via missing player.
        }
    }

    private func makeTimelineThumbnails(duration: Double) async {
        let count = 10
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 120, height: 120)
        var frames: [CGImage] = []
        for i in 0..<count {
            let t = duration * Double(i) / Double(count)
            if let image = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image {
                frames.append(image)
            }
        }
        timelineThumbnails = frames
    }

    // MARK: - Save & export

    func save(using env: AppEnvironment) async {
        design.edit = history.current
        design.modifiedAt = Date()
        do {
            try await env.store.saveWallpaperDesign(design)
            env.activeWallpaper = design
            await env.reloadLibrary()
        } catch {
            env.alert = .init(title: "Couldn't save wallpaper", message: error.localizedDescription)
        }
    }

    /// Generates the paired Live Photo assets and validates the result.
    func exportLivePhoto(to directory: URL, quality: ExportQuality, env: AppEnvironment) async {
        isProcessing = true
        exportProgress = 0
        defer { isProcessing = false }
        do {
            let pair = try await generator.generate(
                source: sourceURL, params: history.current, quality: quality,
                outputDirectory: directory, assetIdentifier: design.id) { [weak self] p in
                    Task { @MainActor in self?.exportProgress = p }
                }
            let validation = await generator.validate(pair)
            exportResult = ExportResult(pair: pair, validation: validation, directory: directory)
        } catch {
            exportProgress = nil
            env.alert = .init(title: "Live Photo export failed", message: error.localizedDescription)
        }
    }

    /// Exports just the edited video.
    func exportVideo(to url: URL, quality: ExportQuality, env: AppEnvironment) async {
        guard let edited else { return }
        isProcessing = true
        exportProgress = 0
        defer { isProcessing = false }
        do {
            try await processor.export(edited: edited, to: url, quality: quality) { [weak self] p in
                Task { @MainActor in self?.exportProgress = p }
            }
        } catch {
            env.alert = .init(title: "Video export failed", message: error.localizedDescription)
        }
        exportProgress = nil
    }

    /// Exports the still frame as JPEG.
    func exportStill(to url: URL, env: AppEnvironment) async {
        guard let edited, let still = try? await processor.renderedStill(from: edited) else { return }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, still, [
            kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return }
        do { try (data as Data).write(to: url) }
        catch { env.alert = .init(title: "Export failed", message: error.localizedDescription) }
    }
}
