import SwiftUI
import AVFoundation
import AVKit
import MotifCore
import UniformTypeIdentifiers

/// Wallpaper Studio: design list, live-edited video preview, trim timeline,
/// lock-screen preview, and the Live Photo export pipeline.
struct WallpaperStudioView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedID: UUID?
    @State private var model: WallpaperModel?
    @State private var showVideoImporter = false
    @State private var showStillImporter = false
    @State private var showPairVideoImporter = false
    @State private var pendingPairStill: URL?
    @State private var exportQuality: ExportQuality = .high

    private var designs: [LibraryEntry] {
        env.entries.filter { $0.kind == .wallpaper }
    }

    var body: some View {
        HSplitView {
            designList.frame(minWidth: 190, idealWidth: 210, maxWidth: 250)
            editorArea.frame(minWidth: 480)
            inspector.frame(minWidth: 250, idealWidth: 280, maxWidth: 320)
        }
        .navigationTitle("Wallpaper Studio")
        .fileImporter(isPresented: $showVideoImporter,
                      allowedContentTypes: [.mpeg4Movie, .quickTimeMovie]) { result in
            if case .success(let url) = result {
                Task { if let d = await env.importVideo(from: url) { selectedID = d.id } }
            }
        }
        .fileImporter(isPresented: $showStillImporter,
                      allowedContentTypes: [.jpeg, .heic, .png]) { result in
            if case .success(let url) = result {
                pendingPairStill = url
                showPairVideoImporter = true
            }
        }
        .fileImporter(isPresented: $showPairVideoImporter,
                      allowedContentTypes: [.quickTimeMovie, .mpeg4Movie]) { result in
            if case .success(let video) = result, let still = pendingPairStill {
                Task {
                    if let d = await env.importLivePhotoPair(still: still, video: video) {
                        selectedID = d.id
                    }
                    pendingPairStill = nil
                }
            }
        }
        .onChange(of: selectedID) { _, id in openDesign(id) }
        .onAppear { if selectedID == nil { selectedID = designs.first?.id } }
    }

    // MARK: - List

    private var designList: some View {
        VStack(spacing: 0) {
            List(designs, selection: $selectedID) { entry in
                HStack(spacing: 10) {
                    if let design = entry.wallpaperDesign {
                        ThumbnailView(assetID: entry.id, sourceURL: env.videoURL(for: design))
                            .frame(width: 34, height: 60)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text(entry.modifiedAt, style: .date)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .tag(entry.id)
                .contextMenu {
                    Button("Duplicate") {
                        Task { _ = try? await env.store.duplicate(id: entry.id); await env.reloadLibrary() }
                    }
                    Button("Export Bundle…") { exportBundle(entry) }
                    Divider()
                    Button("Delete…", role: .destructive) {
                        Task { try? await env.store.delete(id: entry.id); await env.reloadLibrary() }
                    }
                }
            }
            .listStyle(.plain)

            Menu {
                Button("Import Video…") { showVideoImporter = true }
                Button("Import Live Photo Pair…") { showStillImporter = true }
            } label: {
                Label("New", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .padding(8)
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorArea: some View {
        if let model {
            VStack(spacing: 16) {
                preview(model)
                if let info = model.info {
                    TrimTimelineView(
                        start: binding(\.trimStart),
                        end: binding(\.trimEnd),
                        still: binding(\.stillTime),
                        duration: info.duration,
                        thumbnails: model.timelineThumbnails
                    )
                    .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top, 20)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(.tertiary)
                Text("No video selected")
                    .font(.title3.weight(.medium))
                Text("Import an MP4 or MOV — or an existing Live Photo pair.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Import Video…") { showVideoImporter = true }
                    Button("Import Live Photo Pair…") { showStillImporter = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        if let d = await env.importVideo(from: url) { selectedID = d.id }
                    }
                }
                return true
            }
        }
    }

    private func preview(_ model: WallpaperModel) -> some View {
        HStack(spacing: 24) {
            // Live-edited playback preview.
            VStack(spacing: 8) {
                Group {
                    if let player = model.player {
                        VideoPlayer(player: player)
                            .aspectRatio(preset.aspectRatio, contentMode: .fit)
                    } else {
                        Rectangle().fill(.quaternary)
                            .aspectRatio(preset.aspectRatio, contentMode: .fit)
                            .overlay(ProgressView())
                    }
                }
                .frame(maxHeight: 340)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 12) {
                    Button { model.player?.play() } label: { Image(systemName: "play.fill") }
                    Button { model.player?.pause() } label: { Image(systemName: "pause.fill") }
                    Toggle("Compare original", isOn: Binding(
                        get: { model.compareOriginal }, set: { model.compareOriginal = $0 }))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                .font(.caption)
            }

            // Lock screen still preview.
            VStack(spacing: 8) {
                LockScreenPreview(
                    image: model.compareOriginal ? model.originalStill : model.lockScreenStill,
                    preset: preset,
                    dimmed: false,
                    height: 340)
                Text("Lock-screen preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
    }

    private var preset: DisplayPreset {
        DisplayPreset.preset(withID: model?.edit.presetID ?? DisplayPreset.iPhone14Plus.id)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let model {
            WallpaperInspector(
                model: model, preset: preset,
                exportQuality: $exportQuality)
        } else {
            Text("Select or import a video.")
                .font(.callout).foregroundStyle(.secondary)
                .padding()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<VideoEditParameters, Double>) -> Binding<Double> {
        Binding(
            get: { model?.edit[keyPath: keyPath] ?? 0 },
            set: { value in
                model?.beginStroke()
                model?.updateInPlace { $0[keyPath: keyPath] = value }
                model?.endStroke()
            })
    }

    // MARK: - Actions

    private func openDesign(_ id: UUID?) {
        guard let id, let entry = env.entry(for: id), let design = entry.wallpaperDesign else {
            model = nil
            return
        }
        model = WallpaperModel(design: design, sourceURL: env.videoURL(for: design))
        env.activeWallpaper = design
    }

    private func exportBundle(_ entry: LibraryEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(entry.title).motifdesign.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let data = try await env.store.exportBundle(id: entry.id)
                    try data.write(to: url)
                } catch {
                    env.alert = .init(title: "Export failed", message: error.localizedDescription)
                }
            }
        }
    }
}

/// Right-hand inspector for the wallpaper editor.
struct WallpaperInspector: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: WallpaperModel
    let preset: DisplayPreset
    @Binding var exportQuality: ExportQuality

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Motif.Metrics.gap) {

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Device preset",
                                  subtitle: preset.name)
                    Picker("Preset", selection: binding(\.presetID)) {
                        ForEach(DisplayPreset.all) { p in
                            Text("\(p.name) · \(p.pixelWidth)×\(p.pixelHeight)").tag(p.id)
                        }
                    }
                    .labelsHidden()
                    if let device = env.deviceManager.selectedDevice,
                       let auto = DisplayPreset.preset(forProductType: device.productType),
                       auto.id != model.edit.presetID {
                        Button("Use \(auto.name) (connected)") {
                            model.update { $0.presetID = auto.id }
                        }
                        .controlSize(.small)
                    }
                }
                .panel()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Frame")
                    SliderRow(label: "Zoom", value: binding(\.zoom), range: 1...4,
                              format: { String(format: "%.1f×", $0) })
                    SliderRow(label: "Pan X", value: binding(\.offsetX), range: -1...1,
                              format: { String(format: "%+.2f", $0) })
                    SliderRow(label: "Pan Y", value: binding(\.offsetY), range: -1...1,
                              format: { String(format: "%+.2f", $0) })
                    SliderRow(label: "Speed", value: binding(\.speed), range: 0.5...2,
                              format: { String(format: "%.1f×", $0) })
                    Toggle("Remove audio", isOn: Binding(
                        get: { model.edit.muted },
                        set: { newValue in model.update { $0.muted = newValue } }))
                        .font(.callout)
                    HStack {
                        Button("Reset") { model.reset() }
                        Spacer()
                        Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(!model.history.canUndo)
                            .keyboardShortcut("z", modifiers: [.command])
                        Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                            .disabled(!model.history.canRedo)
                            .keyboardShortcut("z", modifiers: [.command, .shift])
                    }
                }
                .panel()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Export")
                    Picker("Quality", selection: $exportQuality) {
                        ForEach(ExportQuality.allCases, id: \.self) { q in
                            Text(q.displayName).tag(q)
                        }
                    }
                    .labelsHidden()

                    if let progress = model.exportProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }

                    VStack(spacing: 8) {
                        Button { exportLivePhoto() } label: {
                            Label("Export Live Photo Pair…", systemImage: "livephoto")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isProcessing)

                        HStack {
                            Button("Video…") { exportVideo() }.disabled(model.isProcessing)
                            Button("Still…") { exportStill() }.disabled(model.isProcessing)
                        }
                    }
                }
                .panel()

                if let result = model.exportResult {
                    resultCard(result)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "About lock-screen animation")
                    Text("A structurally valid Live Photo imports into Photos as one. Whether it animates on your lock screen depends on your iOS version — verify on the device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .panel()
            }
            .padding(Motif.Metrics.gap)
        }
    }

    private func resultCard(_ result: WallpaperModel.ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Export result")
            HStack {
                StatusBadge(
                    result.validation.isStructurallyValid
                        ? "Valid Live Photo pair" : "Invalid pair",
                    color: result.validation.isStructurallyValid ? Motif.Colors.ok : Motif.Colors.bad)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.directory])
                }
                .controlSize(.small)
            }
            CheckRow(ok: result.validation.stillHasIdentifier, text: "Still carries pairing ID")
            CheckRow(ok: result.validation.videoHasIdentifier, text: "Video carries pairing ID")
            CheckRow(ok: result.validation.identifiersMatch, text: "Identifiers match")
            CheckRow(ok: result.validation.hasTimedMetadataTrack, text: "Still-image-time track present")
            Text("Unverified: lock-screen playback on the target device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panel()
    }

    private struct CheckRow: View {
        let ok: Bool
        let text: String
        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(ok ? Motif.Colors.ok : Motif.Colors.bad)
                Text(text).font(.caption)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<VideoEditParameters, Double>) -> Binding<Double> {
        Binding(
            get: { model.edit[keyPath: keyPath] },
            set: { value in
                model.beginStroke()
                model.updateInPlace { $0[keyPath: keyPath] = value }
                model.endStroke()
            })
    }

    private func binding(_ keyPath: WritableKeyPath<VideoEditParameters, String>) -> Binding<String> {
        Binding(
            get: { model.edit[keyPath: keyPath] },
            set: { newValue in model.update { $0[keyPath: keyPath] = newValue } })
    }

    private func exportLivePhoto() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Export here"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.exportLivePhoto(to: url, quality: exportQuality, env: env) }
        }
    }

    private func exportVideo() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = "\(model.design.title).mov"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.exportVideo(to: url, quality: exportQuality, env: env) }
        }
    }

    private func exportStill() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "\(model.design.title).jpg"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.exportStill(to: url, env: env) }
        }
    }
}
