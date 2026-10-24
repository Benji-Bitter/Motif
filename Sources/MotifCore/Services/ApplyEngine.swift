import Foundation
import CoreImage

/// Everything the apply pipeline needs to know about the current request.
public struct ApplyContext: Sendable {
    public var device: DeviceInfo?
    public var cardDesign: CardDesign?
    /// Original artwork file for the card design.
    public var cardArtworkSource: URL?
    public var wallpaperDesign: WallpaperDesign?
    /// Source video file for the wallpaper design.
    public var videoSource: URL?
    /// Where generated assets are written.
    public var outputDirectory: URL
    public var exportQuality: ExportQuality

    public init(
        device: DeviceInfo? = nil,
        cardDesign: CardDesign? = nil,
        cardArtworkSource: URL? = nil,
        wallpaperDesign: WallpaperDesign? = nil,
        videoSource: URL? = nil,
        outputDirectory: URL,
        exportQuality: ExportQuality = .high
    ) {
        self.device = device
        self.cardDesign = cardDesign
        self.cardArtworkSource = cardArtworkSource
        self.wallpaperDesign = wallpaperDesign
        self.videoSource = videoSource
        self.outputDirectory = outputDirectory
        self.exportQuality = exportQuality
    }
}

/// Central customisation workflow. Plans every requested operation, reports
/// honest per-operation statuses, and only marks operations succeeded after
/// they actually completed and were checked.
public actor ApplyEngine {
    private let walletProvider: WalletSkinProviding
    private let transferProvider: LivePhotoTransferProviding
    private let imageProcessor = ImageProcessor()
    private let livePhotoGenerator: LivePhotoGenerator

    public init(
        walletProvider: WalletSkinProviding = UnverifiedWalletSkinProvider(),
        transferProvider: LivePhotoTransferProviding = ManualInstallTransferProvider(),
        livePhotoGenerator: LivePhotoGenerator = LivePhotoGenerator()
    ) {
        self.walletProvider = walletProvider
        self.transferProvider = transferProvider
        self.livePhotoGenerator = livePhotoGenerator
    }

    // MARK: - Planning

    /// Evaluates every requested operation against the device so the UI can
    /// show exactly what will happen *before* the user confirms anything.
    public func plan(for context: ApplyContext) -> [ApplyOperation] {
        var operations: [ApplyOperation] = []

        if let design = context.cardDesign, context.cardArtworkSource != nil {
            let support = walletProvider.support(for: context.device)
            operations.append(ApplyOperation(
                kind: .cardSkinInstall,
                title: "Install card artwork “\(design.title)”",
                status: map(support),
                detail: support.detail))
        }

        if let design = context.wallpaperDesign, context.videoSource != nil {
            operations.append(ApplyOperation(
                kind: .livePhotoExport,
                title: "Generate Live Photo “\(design.title)”",
                status: .supported,
                detail: "Rendered locally on this Mac"))
            let transferSupport = transferProvider.support(for: context.device)
            operations.append(ApplyOperation(
                kind: .livePhotoTransfer,
                title: "Transfer wallpaper to iPhone",
                status: map(transferSupport),
                detail: transferSupport.detail))
        }

        return operations
    }

    /// Reasons the apply button should be blocked entirely.
    public func blockers(for context: ApplyContext, plan: [ApplyOperation]) -> [String] {
        var blockers: [String] = []
        if context.cardDesign == nil && context.wallpaperDesign == nil {
            blockers.append("Select a card design or wallpaper to apply.")
        }
        if plan.isEmpty {
            blockers.append("Nothing to apply.")
        }
        // Device presence is required for the workflow even though every
        // currently-shipping provider ultimately reports manual/unsupported —
        // honest messaging beats a fake Apply.
        if context.device == nil {
            blockers.append("Connect an iPhone over USB.")
        } else if context.device?.connectionState != .ready {
            blockers.append("The iPhone must be unlocked and trusted before applying.")
        }
        return blockers
    }

    // MARK: - Execution

    /// Runs the plan, streaming each operation as its status changes.
    /// Callers must confirm with the user before starting.
    public func execute(
        context: ApplyContext,
        plan: [ApplyOperation],
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> AsyncThrowingStream<ApplyOperation, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var generatedPair: LivePhotoPair?

                for operation in plan {
                    var op = operation
                    func update(_ status: OperationStatus, detail: String? = nil) {
                        op.status = status
                        if let detail { op.detail = detail }
                        continuation.yield(op)
                    }

                    switch operation.kind {
                    case .cardSkinInstall:
                        guard let design = context.cardDesign,
                              let source = context.cardArtworkSource else {
                            update(.failed("Missing card design"), detail: "Internal error")
                            continue
                        }
                        let support = walletProvider.support(for: context.device)
                        guard case .supported = support else {
                            update(map(support), detail: support.detail)
                            continue
                        }
                        do {
                            update(.preparing)
                            let artwork = try renderCardArtwork(design: design, source: source,
                                                                into: context.outputDirectory)
                            update(.applying)
                            guard let device = context.device else {
                                update(.failed("No device"), detail: nil)
                                continue
                            }
                            let outcome = try await walletProvider.apply(
                                design: design, renderedArtwork: artwork, to: device)
                            switch outcome {
                            case .applied(let detail):
                                update(.succeeded(detail))
                            case .manualExport(let dir, let instructions):
                                update(.requiresManual(instructions), detail: dir.path)
                            }
                        } catch {
                            update(.failed(error.localizedDescription))
                        }

                    case .livePhotoExport:
                        guard let design = context.wallpaperDesign,
                              let source = context.videoSource else {
                            update(.failed("Missing wallpaper design"))
                            continue
                        }
                        update(.preparing)
                        do {
                            let outDir = context.outputDirectory
                                .appendingPathComponent("LivePhoto-\(design.id.uuidString.prefix(8))")
                            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                            generatedPair = try await livePhotoGenerator.generate(
                                source: source, params: design.edit,
                                quality: context.exportQuality,
                                outputDirectory: outDir,
                                assetIdentifier: design.id,
                                progress: progress)
                            update(.succeeded("Pair exported to \(outDir.lastPathComponent)"),
                                   detail: outDir.path)
                        } catch {
                            update(.failed(error.localizedDescription))
                        }

                    case .livePhotoTransfer:
                        guard generatedPair != nil else {
                            update(.failed("Skipped — Live Photo export did not succeed"))
                            continue
                        }
                        let support = transferProvider.support(for: context.device)
                        update(.applying)
                        do {
                            let outcome = try await transferProvider.apply(
                                pair: generatedPair!, to: context.device,
                                outputDirectory: context.outputDirectory)
                            switch outcome {
                            case .applied(let detail):
                                update(.succeeded(detail))
                            case .manualExport(_, let instructions):
                                update(.requiresManual(instructions), detail: support.detail)
                            }
                        } catch {
                            update(.failed(error.localizedDescription))
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    private func renderCardArtwork(design: CardDesign, source: URL, into directory: URL) throws -> URL {
        let image = try imageProcessor.loadCIImage(from: source)
        let rendered = try CardArtworkRenderer.render(
            source: image, params: design.edit,
            outputSize: CardExportPreset.standard.pixelSize,
            processor: imageProcessor)
        let url = directory.appendingPathComponent("\(design.id.uuidString)-card.png")
        try imageProcessor.writePNG(rendered, to: url)
        return url
    }

    private func map(_ support: ProviderSupport) -> OperationStatus {
        switch support {
        case .supported: return .supported
        case .requiresManual(let d): return .requiresManual(d)
        case .notTested(let d): return .notTested(d)
        case .unsupported(let d): return .unsupported(d)
        }
    }
}
