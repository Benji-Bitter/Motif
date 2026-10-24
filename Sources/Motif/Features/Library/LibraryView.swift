import SwiftUI
import MotifCore
import UniformTypeIdentifiers

/// The local design library: everything saved lives here — searchable,
/// taggable, grouped into collections, exportable as portable bundles.
struct LibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var search = ""
    @State private var kindFilter: AssetKind? = nil
    @State private var favoritesOnly = false
    @State private var collectionFilter: UUID?
    @State private var tagFilter: String?
    @State private var allTags: [String] = []
    @State private var renameTarget: LibraryEntry?
    @State private var showImporter = false

    private var filtered: [LibraryEntry] {
        env.entries.filter { entry in
            if let kindFilter, entry.kind != kindFilter { return false }
            if favoritesOnly, !entry.isFavorite { return false }
            if let collectionFilter, entry.collectionID != collectionFilter { return false }
            if let tagFilter, !entry.tags.contains(tagFilter) { return false }
            if !search.isEmpty,
               !entry.title.localizedCaseInsensitiveContains(search),
               !entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) }) {
                return false
            }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Motif.Metrics.gap * 1.5) {
                filterBar
                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        ForEach(filtered) { entry in
                            AssetCell(entry: entry, onRename: { renameTarget = $0 })
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Import Design Bundle…") { showImporter = true }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
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
        .task(id: env.entries) { allTags = (try? await env.store.allTags()) ?? [] }
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search library", text: $search).textFieldStyle(.plain)
                }
                .padding(7)
                .background(Motif.Colors.panelFill, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 280)

                Picker("Kind", selection: $kindFilter) {
                    Text("All").tag(AssetKind?.none)
                    Text("Cards").tag(AssetKind?.some(.card))
                    Text("Wallpapers").tag(AssetKind?.some(.wallpaper))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Picker("Collection", selection: $collectionFilter) {
                    Text("All collections").tag(UUID?.none)
                    ForEach(env.collections) { collection in
                        Text(collection.name).tag(UUID?.some(collection.id))
                    }
                }
                .frame(maxWidth: 200)

                Toggle("Favorites", isOn: $favoritesOnly)
                    .toggleStyle(.checkbox)
                Spacer()
            }

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                tagFilter = tagFilter == tag ? nil : tag
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(tagFilter == tag ? Color.primary.opacity(0.2) : Motif.Colors.panelFill,
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .panel()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Nothing matches")
                .font(.headline)
            Text("Adjust the filters, or create something in the studios.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
        .panel()
    }

    private func importBundle(_ url: URL) async {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            let data = try Data(contentsOf: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
            _ = try await env.store.importBundle(data: data)
            await env.reloadLibrary()
        } catch {
            env.alert = .init(title: "Couldn't import design", message: error.localizedDescription)
        }
    }

    // MARK: - Cell

    private struct AssetCell: View {
        @EnvironmentObject private var env: AppEnvironment
        let entry: LibraryEntry
        var onRename: (LibraryEntry) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer()
                        if entry.isFavorite {
                            Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(entry.kind == .card ? "Card" : "Wallpaper")
                        Text("·")
                        Text(entry.modifiedAt, style: .date)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    if !entry.tags.isEmpty {
                        Text(entry.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            .padding(10)
            .background(Motif.Colors.panelFill, in: RoundedRectangle(cornerRadius: Motif.Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Motif.Metrics.corner)
                .strokeBorder(Motif.Colors.panelStroke))
            .contextMenu { menu }
        }

        private var thumbnail: some View {
            Group {
                if let design = entry.cardDesign {
                    ThumbnailView(assetID: entry.id, sourceURL: env.artworkURL(for: design), maxPixel: 400)
                        .aspectRatio(contentMode: .fit)
                } else if let design = entry.wallpaperDesign {
                    ThumbnailView(assetID: entry.id, sourceURL: env.videoURL(for: design), maxPixel: 400)
                        .aspectRatio(contentMode: .fit)
                }
            }
        }

        @ViewBuilder
        private var menu: some View {
            Button(entry.isFavorite ? "Unfavorite" : "Favorite") {
                Task { try? await env.store.setFavorite(id: entry.id, !entry.isFavorite); await env.reloadLibrary() }
            }
            Button("Rename…") { onRename(entry) }
            Button("Duplicate") {
                Task { _ = try? await env.store.duplicate(id: entry.id); await env.reloadLibrary() }
            }
            Menu("Add Tag") {
                Button("example") { Task { try? await env.store.addTag(id: entry.id, tag: "example"); await env.reloadLibrary() } }
                Button("favorite") { Task { try? await env.store.addTag(id: entry.id, tag: "favorite"); await env.reloadLibrary() } }
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
            }
            Divider()
            Button("Export Design Bundle…") { exportBundle(entry) }
            Button("Reveal in Finder") { reveal(entry) }
            Divider()
            Button("Delete…", role: .destructive) { delete(entry) }
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

        private func reveal(_ entry: LibraryEntry) {
            let url = entry.kind == .card
                ? entry.cardDesign.map { env.artworkURL(for: $0) }
                : entry.wallpaperDesign.map { env.videoURL(for: $0) }
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }

        private func delete(_ entry: LibraryEntry) {
            Task {
                try? await env.store.delete(id: entry.id)
                await env.reloadLibrary()
            }
        }
    }
}
