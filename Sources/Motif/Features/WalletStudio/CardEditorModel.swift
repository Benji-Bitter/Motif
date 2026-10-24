import SwiftUI
import CoreImage
import MotifCore

/// Editor state for one card design. Owns the loaded source image, the
/// undo/redo history and the debounced preview render.
@MainActor
final class CardEditorModel: ObservableObject {
    @Published private(set) var design: CardDesign
    @Published private(set) var preview: CGImage?
    @Published private(set) var isRendering = false
    @Published private(set) var history: EditHistory<CardEditParameters>

    private(set) var source: CIImage?
    private let processor = ImageProcessor()
    private var renderTask: Task<Void, Never>?

    var edit: CardEditParameters { history.current }

    init(design: CardDesign, artworkURL: URL) {
        self.design = design
        self.history = EditHistory(design.edit)
        do {
            self.source = try processor.loadCIImage(from: artworkURL)
            scheduleRender()
        } catch {
            self.source = nil
        }
    }

    // MARK: - Edits

    /// Discrete change — one undo step.
    func update(_ mutate: (inout CardEditParameters) -> Void) {
        var next = history.current
        mutate(&next)
        history.push(next)
        scheduleRender()
    }

    /// Continuous gesture pattern: begin → updateInPlace×N → endStroke.
    func beginStroke() { history.beginStroke() }
    func updateInPlace(_ mutate: (inout CardEditParameters) -> Void) {
        var next = history.current
        mutate(&next)
        history.updateInPlace(next)
        scheduleRender(debounce: .milliseconds(30))
    }
    func endStroke() {
        history.endStroke()
        design.edit = history.current
    }

    func undo() { if history.undo() { design.edit = history.current; scheduleRender() } }
    func redo() { if history.redo() { design.edit = history.current; scheduleRender() } }
    func reset() {
        history.reset(to: .default)
        design.edit = history.current
        scheduleRender()
    }

    // MARK: - Rendering

    /// Debounced preview render at a modest size — the same pipeline as export.
    private func scheduleRender(debounce: Duration = .milliseconds(50)) {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard let self, !Task.isCancelled else { return }
            await self.renderPreview()
        }
    }

    private func renderPreview() async {
        guard let source else { return }
        isRendering = true
        let params = history.current
        let result = await Task.detached(priority: .userInitiated) {
            try? CardArtworkRenderer.renderPreview(
                source: source, params: params, maxPixelWidth: 720,
                processor: ImageProcessor())
        }.value
        if !Task.isCancelled, let result {
            preview = result
        }
        isRendering = false
    }

    // MARK: - Persistence & export

    /// Persists edits and refreshes the stored thumbnail (the *rendered* card,
    /// not the raw artwork).
    func save(using env: AppEnvironment) async {
        design.edit = history.current
        design.modifiedAt = Date()
        do {
            try await env.store.saveCardDesign(design)
            if let thumb = try? CardArtworkRenderer.render(
                source: source!, params: design.edit,
                outputSize: CGSize(width: 480, height: 480 / CardGeometry.aspectRatio),
                processor: processor) {
                env.thumbnails.storeThumbnail(thumb, assetID: design.id)
            }
            env.activeCard = design
            await env.reloadLibrary()
        } catch {
            env.alert = .init(title: "Couldn't save design", message: error.localizedDescription)
        }
    }

    /// Renders the card at an export preset and writes a PNG.
    func exportPNG(to url: URL, preset: CardExportPreset, env: AppEnvironment) async {
        guard let source else { return }
        let params = history.current
        do {
            let rendered = try await Task.detached(priority: .userInitiated) {
                try CardArtworkRenderer.render(
                    source: source, params: params,
                    outputSize: preset.pixelSize, processor: ImageProcessor())
            }.value
            try processor.writePNG(rendered, to: url)
        } catch {
            env.alert = .init(title: "Export failed", message: error.localizedDescription)
        }
    }
}
