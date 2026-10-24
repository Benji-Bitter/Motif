import Foundation

public enum LibraryError: Error, Equatable, Sendable {
    case notFound(UUID)
    case invalidBundle(String)
    case unsupportedBundleVersion(Int)
    case databaseCorrupt(String)
}

/// The local design library: a SQLite metadata index over files stored in the
/// library directory. All methods are serialized through the actor.
///
/// Layout on disk:
///   root/library.sqlite         — metadata index
///   root/Files/<uuid>.<ext>     — original imported media (never re-encoded)
///   root/Thumbnails/<uuid>.jpg  — generated thumbnails
///   root/Exports/…              — exported artwork / Live Photo pairs
public actor LibraryStore {
    public nonisolated let paths: LibraryPaths
    private let db: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(paths: LibraryPaths) throws {
        self.paths = paths
        try paths.ensureExists()
        db = try SQLiteDatabase(path: paths.database.path)
        try Self.migrate(db)
    }

    /// Convenience initializer used by the app.
    public static func defaultStore() throws -> LibraryStore {
        try LibraryStore(paths: .default())
    }

    private static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS assets(
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                modified_at REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                collection_id TEXT,
                payload BLOB NOT NULL
            );
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS collections(
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT,
                created_at REAL NOT NULL
            );
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS tags(
                asset_id TEXT NOT NULL,
                tag TEXT NOT NULL,
                PRIMARY KEY(asset_id, tag)
            );
            """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS recent_imports(
                id TEXT PRIMARY KEY,
                original_name TEXT NOT NULL,
                stored_file TEXT NOT NULL,
                kind TEXT NOT NULL,
                imported_at REAL NOT NULL
            );
            """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_assets_kind ON assets(kind);")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_assets_modified ON assets(modified_at DESC);")
    }

    // MARK: - File storage

    /// Copies an imported media file into the library under a stable name and
    /// records it as a recent import. Returns the stored file name.
    @discardableResult
    public func storeMedia(from url: URL, kind: AssetKind) throws -> String {
        let id = UUID()
        let fileName = ImportValidator.storedFileName(for: id, original: url)
        let destination = paths.files.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw FileError.copyFailed(error.localizedDescription)
        }
        try db.run(
            "INSERT OR REPLACE INTO recent_imports(id, original_name, stored_file, kind, imported_at) VALUES(?,?,?,?,?)",
            [.text(id.uuidString), .text(url.lastPathComponent), .text(fileName), .text(kind.rawValue), .real(Date().timeIntervalSince1970)]
        )
        return fileName
    }

    /// Stores already-on-disk data (e.g. generated example art) as library media.
    public func storeMediaData(_ data: Data, fileName: String) throws -> String {
        let destination = paths.files.appendingPathComponent(fileName)
        try AtomicFile.write(data, to: destination)
        return fileName
    }

    /// Absolute URL for a stored media file name.
    public func mediaURL(fileName: String) -> URL {
        paths.files.appendingPathComponent(fileName)
    }

    public func thumbnailURL(for id: UUID) -> URL {
        paths.thumbnails.appendingPathComponent("\(id.uuidString).jpg")
    }

    // MARK: - Card designs

    public func saveCardDesign(_ design: CardDesign) throws {
        let data = try encoder.encode(design)
        try upsertAsset(id: design.id, kind: .card, title: design.title,
                        createdAt: design.createdAt, modifiedAt: design.modifiedAt, payload: data)
    }

    public func cardDesign(id: UUID) throws -> CardDesign {
        guard let entry = try entry(id: id), let design = entry.cardDesign else {
            throw LibraryError.notFound(id)
        }
        return design
    }

    public func saveWallpaperDesign(_ design: WallpaperDesign) throws {
        let data = try encoder.encode(design)
        try upsertAsset(id: design.id, kind: .wallpaper, title: design.title,
                        createdAt: design.createdAt, modifiedAt: design.modifiedAt, payload: data)
    }

    public func wallpaperDesign(id: UUID) throws -> WallpaperDesign {
        guard let entry = try entry(id: id), let design = entry.wallpaperDesign else {
            throw LibraryError.notFound(id)
        }
        return design
    }

    /// Deep-copies a design and its source media under a new id.
    @discardableResult
    public func duplicate(id: UUID) throws -> LibraryEntry {
        guard let existing = try entry(id: id) else { throw LibraryError.notFound(id) }
        let newID = UUID()
        switch existing.kind {
        case .card:
            guard var design = existing.cardDesign else { throw LibraryError.databaseCorrupt("card payload") }
            design.artworkFileName = try duplicateMedia(fileName: design.artworkFileName, newID: newID)
            design.id = newID
            design.title = existing.title + " Copy"
            design.createdAt = Date()
            design.modifiedAt = Date()
            try saveCardDesign(design)
        case .wallpaper:
            guard var design = existing.wallpaperDesign else { throw LibraryError.databaseCorrupt("wallpaper payload") }
            design.sourceFileName = try duplicateMedia(fileName: design.sourceFileName, newID: newID)
            design.id = newID
            design.title = existing.title + " Copy"
            design.createdAt = Date()
            design.modifiedAt = Date()
            try saveWallpaperDesign(design)
        }
        guard let newEntry = try entry(id: newID) else { throw LibraryError.databaseCorrupt("duplicate") }
        return newEntry
    }

    private func duplicateMedia(fileName: String, newID: UUID) throws -> String {
        let ext = (fileName as NSString).pathExtension
        let newName = "\(newID.uuidString).\(ext)"
        try FileManager.default.copyItem(at: paths.files.appendingPathComponent(fileName),
                                         to: paths.files.appendingPathComponent(newName))
        return newName
    }

    /// Deletes the row, tags, thumbnail and owned media file.
    public func delete(id: UUID) throws {
        guard let entry = try entry(id: id) else { throw LibraryError.notFound(id) }
        let fileName = entry.kind == .card
            ? entry.cardDesign?.artworkFileName
            : entry.wallpaperDesign?.sourceFileName
        try db.run("DELETE FROM tags WHERE asset_id = ?", [.text(id.uuidString)])
        try db.run("DELETE FROM assets WHERE id = ?", [.text(id.uuidString)])
        if let fileName {
            try? FileManager.default.removeItem(at: paths.files.appendingPathComponent(fileName))
        }
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
    }

    // MARK: - Queries

    public func entries(kind: AssetKind? = nil) throws -> [LibraryEntry] {
        let rows: [[String: SQLiteValue]]
        if let kind {
            rows = try db.query(
                "SELECT * FROM assets WHERE kind = ? ORDER BY modified_at DESC", [.text(kind.rawValue)])
        } else {
            rows = try db.query("SELECT * FROM assets ORDER BY modified_at DESC")
        }
        return try rows.map { try rowToEntry($0) }
    }

    public func entry(id: UUID) throws -> LibraryEntry? {
        let rows = try db.query("SELECT * FROM assets WHERE id = ?", [.text(id.uuidString)])
        return try rows.first.map { try rowToEntry($0) }
    }

    /// Title/tag/collection search. Empty query returns everything.
    public func search(_ query: String, kind: AssetKind? = nil) throws -> [LibraryEntry] {
        let all = try entries(kind: kind)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { entry in
            entry.title.lowercased().contains(needle)
                || entry.tags.contains { $0.lowercased().contains(needle) }
        }
    }

    // MARK: - Flags / tags / collections

    public func rename(id: UUID, title: String) throws {
        try db.run("UPDATE assets SET title = ?, modified_at = ? WHERE id = ?",
                   [.text(title), .real(Date().timeIntervalSince1970), .text(id.uuidString)])
        // Keep the payload title in sync so exported bundles stay consistent.
        if let entry = try entry(id: id) {
            if var design = entry.cardDesign {
                design.title = title; design.modifiedAt = Date()
                try db.run("UPDATE assets SET payload = ? WHERE id = ?",
                           [.blob(try encoder.encode(design)), .text(id.uuidString)])
            } else if var design = entry.wallpaperDesign {
                design.title = title; design.modifiedAt = Date()
                try db.run("UPDATE assets SET payload = ? WHERE id = ?",
                           [.blob(try encoder.encode(design)), .text(id.uuidString)])
            }
        }
    }

    public func setFavorite(id: UUID, _ favorite: Bool) throws {
        try db.run("UPDATE assets SET is_favorite = ? WHERE id = ?",
                   [.integer(favorite ? 1 : 0), .text(id.uuidString)])
    }

    public func setCollection(id: UUID, collection: UUID?) throws {
        try db.run("UPDATE assets SET collection_id = ? WHERE id = ?",
                   [collection.map { .text($0.uuidString) } ?? .null, .text(id.uuidString)])
    }

    public func addTag(id: UUID, tag: String) throws {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try db.run("INSERT OR IGNORE INTO tags(asset_id, tag) VALUES(?,?)",
                   [.text(id.uuidString), .text(trimmed)])
    }

    public func removeTag(id: UUID, tag: String) throws {
        try db.run("DELETE FROM tags WHERE asset_id = ? AND tag = ?",
                   [.text(id.uuidString), .text(tag)])
    }

    public func allTags() throws -> [String] {
        try db.query("SELECT DISTINCT tag FROM tags ORDER BY tag").compactMap { $0["tag"]?.text }
    }

    public func createCollection(name: String, kind: AssetKind? = nil) throws -> DesignCollection {
        let collection = DesignCollection(name: name, kind: kind)
        try db.run("INSERT INTO collections(id, name, kind, created_at) VALUES(?,?,?,?)",
                   [.text(collection.id.uuidString), .text(name), collection.kind.map { .text($0.rawValue) } ?? .null,
                    .real(collection.createdAt.timeIntervalSince1970)])
        return collection
    }

    public func collections() throws -> [DesignCollection] {
        try db.query("SELECT * FROM collections ORDER BY name").map { row in
            DesignCollection(
                id: UUID(uuidString: row["id"]?.text ?? "") ?? UUID(),
                name: row["name"]?.text ?? "Untitled",
                kind: row["kind"]?.text.flatMap { AssetKind(rawValue: $0) },
                createdAt: Date(timeIntervalSince1970: row["created_at"]?.real ?? 0)
            )
        }
    }

    public func deleteCollection(id: UUID) throws {
        try db.run("UPDATE assets SET collection_id = NULL WHERE collection_id = ?", [.text(id.uuidString)])
        try db.run("DELETE FROM collections WHERE id = ?", [.text(id.uuidString)])
    }

    public func recentImports(limit: Int = 20) throws -> [RecentImport] {
        try db.query("SELECT * FROM recent_imports ORDER BY imported_at DESC LIMIT ?", [.integer(Int64(limit))])
            .map { row in
                RecentImport(
                    id: UUID(uuidString: row["id"]?.text ?? "") ?? UUID(),
                    originalName: row["original_name"]?.text ?? "",
                    storedFileName: row["stored_file"]?.text ?? "",
                    kind: AssetKind(rawValue: row["kind"]?.text ?? "") ?? .card,
                    importedAt: Date(timeIntervalSince1970: row["imported_at"]?.real ?? 0)
                )
            }
    }

    // MARK: - Design bundle import/export

    /// Serializes a design plus its source media into a portable bundle.
    public func exportBundle(id: UUID) throws -> Data {
        guard let entry = try entry(id: id) else { throw LibraryError.notFound(id) }
        let mediaFileName: String
        switch entry.kind {
        case .card:
            guard let design = entry.cardDesign else { throw LibraryError.databaseCorrupt("card payload") }
            mediaFileName = design.artworkFileName
        case .wallpaper:
            guard let design = entry.wallpaperDesign else { throw LibraryError.databaseCorrupt("wallpaper payload") }
            mediaFileName = design.sourceFileName
        }
        let mediaURL = paths.files.appendingPathComponent(mediaFileName)
        let mediaData = try Data(contentsOf: mediaURL)
        let bundle = DesignBundle(kind: entry.kind, design: entry.payload,
                                  mediaFileName: mediaFileName, mediaData: mediaData)
        return try encoder.encode(bundle)
    }

    /// Imports a bundle produced by `exportBundle`, writing media into the
    /// library under a fresh id so imports never clobber existing files.
    @discardableResult
    public func importBundle(data: Data) throws -> LibraryEntry {
        let bundle = try decoder.decode(DesignBundle.self, from: data)
        guard bundle.formatVersion <= DesignBundle.currentFormatVersion else {
            throw LibraryError.unsupportedBundleVersion(bundle.formatVersion)
        }
        let newID = UUID()
        let ext = (bundle.mediaFileName as NSString).pathExtension
        let newFileName = "\(newID.uuidString).\(ext.isEmpty ? "bin" : ext)"
        try AtomicFile.write(bundle.mediaData, to: paths.files.appendingPathComponent(newFileName))

        switch bundle.kind {
        case .card:
            var design = try decoder.decode(CardDesign.self, from: bundle.design)
            design.id = newID
            design.artworkFileName = newFileName
            design.modifiedAt = Date()
            try saveCardDesign(design)
        case .wallpaper:
            var design = try decoder.decode(WallpaperDesign.self, from: bundle.design)
            design.id = newID
            design.sourceFileName = newFileName
            design.modifiedAt = Date()
            try saveWallpaperDesign(design)
        }
        guard let stored = try entry(id: newID) else { throw LibraryError.databaseCorrupt("import") }
        return stored
    }

    // MARK: - Internals

    private func upsertAsset(id: UUID, kind: AssetKind, title: String,
                             createdAt: Date, modifiedAt: Date, payload: Data) throws {
        try db.run("""
            INSERT INTO assets(id, kind, title, created_at, modified_at, is_favorite, collection_id, payload)
            VALUES(?,?,?,?,?, COALESCE((SELECT is_favorite FROM assets WHERE id = ?), 0),
                   (SELECT collection_id FROM assets WHERE id = ?), ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                modified_at = excluded.modified_at,
                payload = excluded.payload
            """,
            [.text(id.uuidString), .text(kind.rawValue), .text(title),
             .real(createdAt.timeIntervalSince1970), .real(modifiedAt.timeIntervalSince1970),
             .text(id.uuidString), .text(id.uuidString), .blob(payload)])
    }

    private func rowToEntry(_ row: [String: SQLiteValue]) throws -> LibraryEntry {
        guard let idString = row["id"]?.text, let id = UUID(uuidString: idString),
              let kindRaw = row["kind"]?.text, let kind = AssetKind(rawValue: kindRaw),
              let payload = row["payload"]?.blob else {
            throw LibraryError.databaseCorrupt("asset row")
        }
        let tags = try db.query("SELECT tag FROM tags WHERE asset_id = ? ORDER BY tag", [.text(idString)])
            .compactMap { $0["tag"]?.text }
        return LibraryEntry(
            id: id,
            kind: kind,
            title: row["title"]?.text ?? "Untitled",
            createdAt: Date(timeIntervalSince1970: row["created_at"]?.real ?? 0),
            modifiedAt: Date(timeIntervalSince1970: row["modified_at"]?.real ?? 0),
            isFavorite: (row["is_favorite"]?.integer ?? 0) != 0,
            collectionID: row["collection_id"]?.text.flatMap { UUID(uuidString: $0) },
            tags: tags,
            payload: payload
        )
    }
}
