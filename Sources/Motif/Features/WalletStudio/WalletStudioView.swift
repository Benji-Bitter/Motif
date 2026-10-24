import SwiftUI
import MotifCore
import UniformTypeIdentifiers

/// Wallet Studio: design list on the left, interactive card editor in the
/// middle, adjustment inspector on the right.
struct WalletStudioView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedID: UUID?
    @State private var editor: CardEditorModel?
    @State private var search = ""
    @State private var showImporter = false
    @State private var showBundleImporter = false
    @State private var renameTarget: LibraryEntry?
    @State private var exportPreset = CardExportPreset.standard

    private var designs: [LibraryEntry] {
        env.entries.filter { $0.kind == .card }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        HSplitView {
            designList
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            editorArea
                .frame(minWidth: 420)
            inspector
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
        }
        .navigationTitle("Wallet Studio")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.png, .jpeg, .heic]) { result in
            if case .success(let url) = result {
                Task { if let design = await env.importArtwork(from: url) { selectedID = design.id } }
            }
        }
        .fileImporter(isPresented: $showBundleImporter,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task { await importBundle(url) }
            }
        }
        .sheet(item: $renameTarget) { entry in
            RenameSheet(title: entry.title) { newTitle in
                Task {
                    try? await env.store.rename(id: entry.id, title: newTitle)
                    await env.reloadLibrary()
                }
            }
        }
    }

    // MARK: - Design list

    private var designList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search designs", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Motif.Colors.panelFill, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)

            List(designs, selection: $selectedID) { entry in
                DesignRow(entry: entry)
                    .tag(entry.id)
                    .contextMenu { designMenu(entry) }
            }
            .listStyle(.plain)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button("From Image File…") { showImporter = true }
                    Button("Import Design Bundle…") { showBundleImporter = true }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
        .onChange(of: selectedID) { _, id in openDesign(id) }
        .onAppear { if selectedID == nil { selectedID = designs.first?.id } }
        .onChange(of: env.entries) { _, _ in
            if let selectedID, env.entry(for: selectedID) == nil { self.selectedID = designs.first?.id }
        }
    }

    private struct DesignRow: View {
        @EnvironmentObject private var env: AppEnvironment
        let entry: LibraryEntry
        var body: some View {
            HStack(spacing: 10) {
                if let design = entry.cardDesign {
                    ThumbnailView(assetID: entry.id, sourceURL: env.artworkURL(for: design))
                        .frame(width: 52, height: 52 / CardGeometry.aspectRatio)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(entry.modifiedAt, style: .date)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if entry.isFavorite {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func designMenu(_ entry: LibraryEntry) -> some View {
        Button("Rename…") { renameTarget = entry }
        Button("Duplicate") { Task { _ = try? await env.store.duplicate(id: entry.id); await env.reloadLibrary() } }
        Button(entry.isFavorite ? "Unfavorite" : "Favorite") {
            Task { try? await env.store.setFavorite(id: entry.id, !entry.isFavorite); await env.reloadLibrary() }
        }
        Menu("Add to Collection") {
            ForEach(env.collections) { collection in
                Button(collection.name) {
                    Task {
                        try? await env.store.setCollection(id: entry.id, collection: collection.id)
                        await env.reloadLibrary()
                    }
                }
            }
            if !env.collections.isEmpty { Divider() }
            Button("None") {
                Task { try? await env.store.setCollection(id: entry.id, collection: nil); await env.reloadLibrary() }
            }
        }
        Divider()
        Button("Export Design Bundle…") { exportBundle(entry) }
        Divider()
        Button("Delete…", role: .destructive) { delete(entry) }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorArea: some View {
        if let editor {
            CardEditorView(model: editor)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "creditcard")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(.tertiary)
                Text("No artwork selected")
                    .font(.title3.weight(.medium))
                Text("Import a PNG, JPEG or HEIC image — drag it in, or use + in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Import Artwork…") { showImporter = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.png, .jpeg, .heic, .fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let editor {
                CardInspector(model: editor, exportPreset: $exportPreset)
            } else {
                Text("Select a design to edit.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openDesign(_ id: UUID?) {
        guard let id, let entry = env.entry(for: id), let design = entry.cardDesign else {
            editor = nil
            return
        }
        editor = CardEditorModel(design: design, artworkURL: env.artworkURL(for: design))
        env.activeCard = design
    }

    private func importBundle(_ url: URL) async {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            let data = try Data(contentsOf: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
            let entry = try await env.store.importBundle(data: data)
            await env.reloadLibrary()
            selectedID = entry.id
        } catch {
            env.alert = .init(title: "Couldn't import design", message: error.localizedDescription)
        }
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

    private func delete(_ entry: LibraryEntry) {
        Task {
            try? await env.store.delete(id: entry.id)
            await env.reloadLibrary()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                if let design = await env.importArtwork(from: url) { selectedID = design.id }
            }
        }
        return true
    }
}

/// Interactive card canvas: the rendered artwork inside real card geometry,
/// draggable to pan, magnifyable to zoom.
struct CardEditorView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: CardEditorModel
    @State private var dragBase: (x: Double, y: Double)?
    @State private var zoomBase: Double = 1

    var body: some View {
        GeometryReader { geo in
            let cardW = min(geo.size.width - 48, (geo.size.height - 48) * CardGeometry.aspectRatio)
            let cardH = cardW / CardGeometry.aspectRatio

            ZStack {
                VStack(spacing: 18) {
                    cardView(width: cardW, height: cardH)
                    Text("Drag to reposition · pinch or slider to zoom")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private func cardView(width: CGFloat, height: CGFloat) -> some View {
        let cornerRadius = CardGeometry.cornerRadius(forHeight: height)
        return ZStack {
            if let preview = model.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(ProgressView())
            }
            // Generic chip glyph — decoration only, not bank branding.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                .frame(width: height * 0.16, height: height * 0.13)
                .offset(x: -width / 2 + height * 0.24, y: -height * 0.16)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .gesture(dragGesture(width: width, height: height))
        .gesture(magnifyGesture)
        .onTapGesture(count: 2) { model.reset() }
        .help("Double-click to reset edits")
    }

    private func dragGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragBase == nil {
                    dragBase = (model.edit.offsetX, model.edit.offsetY)
                    model.beginStroke()
                }
                guard let base = dragBase else { return }
                model.updateInPlace {
                    $0.offsetX = base.x + value.translation.width / width
                    $0.offsetY = base.y - value.translation.height / height  // CI y-up
                }
            }
            .onEnded { _ in
                dragBase = nil
                model.endStroke()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomBase == 1 { zoomBase = model.edit.zoom }
                model.beginStroke()
                model.updateInPlace { $0.zoom = max(0.1, min(10, zoomBase * value.magnification)) }
            }
            .onEnded { _ in
                zoomBase = 1
                model.endStroke()
            }
    }
}

/// Right-hand inspector: transform, adjustments, presets, export.
struct CardInspector: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var model: CardEditorModel
    @Binding var exportPreset: CardExportPreset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Motif.Metrics.gap) {
                // Transform
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Frame")
                    SliderRow(label: "Zoom", value: binding(\.zoom), range: 0.5...5,
                              format: { String(format: "%.1f×", $0) })
                    SliderRow(label: "Rotate", value: binding(\.rotationDegrees), range: -45...45,
                              format: { String(format: "%.0f°", $0) })
                }
                .panel()

                // Adjustments
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Adjust")
                    SliderRow(label: "Brightness", value: binding(\.brightness), range: -1...1,
                              format: { String(format: "%+.0f%%", $0 * 100) })
                    SliderRow(label: "Contrast", value: binding(\.contrast), range: 0.25...4,
                              format: { String(format: "%.2f×", $0) })
                    SliderRow(label: "Saturation", value: binding(\.saturation), range: 0...3,
                              format: { String(format: "%.2f×", $0) })
                    SliderRow(label: "Sharpness", value: binding(\.sharpness), range: 0...2,
                              format: { String(format: "%.2f", $0) })
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

                // Export
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Export")
                    Picker("Size", selection: $exportPreset) {
                        ForEach(CardExportPreset.all) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .labelsHidden()
                    HStack {
                        Button { exportPNG() } label: {
                            Label("Export PNG…", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button("Save") { Task { await model.save(using: env) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .panel()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Install on iPhone")
                    Text("No verified jailbreak-free method exists to replace card artwork on current iOS versions. Exported artwork is yours to use elsewhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .panel()
            }
            .padding(Motif.Metrics.gap)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CardEditParameters, Double>) -> Binding<Double> {
        Binding(
            get: { model.edit[keyPath: keyPath] },
            set: { value in
                model.beginStroke()
                model.updateInPlace { $0[keyPath: keyPath] = value }
                model.endStroke()
            })
    }

    private func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(model.design.title).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.exportPNG(to: url, preset: exportPreset, env: env) }
        }
    }
}

/// Labelled slider + value readout used by both studios.
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                Spacer()
                Text(format(value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}
