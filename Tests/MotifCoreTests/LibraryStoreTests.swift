import XCTest
@testable import MotifCore

final class LibraryStoreTests: XCTestCase {

    private var root: URL!
    private var store: LibraryStore!

    override func setUp() async throws {
        root = TestHelpers.tempLibraryRoot()
        store = try LibraryStore(paths: LibraryPaths(root: root))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func importArtwork(named name: String = "art.png") async throws -> String {
        let src = root.appendingPathComponent(name)
        try TestHelpers.writePNG(TestHelpers.makeTestImage(), to: src)
        return try await store.storeMedia(from: src, kind: .card)
    }

    // MARK: - CRUD

    func testSaveAndFetchCardDesign() async throws {
        let fileName = try await importArtwork()
        var design = CardDesign(title: "Sunset", artworkFileName: fileName)
        design.edit.brightness = 0.3
        try await store.saveCardDesign(design)

        let fetched = try await store.cardDesign(id: design.id)
        XCTAssertEqual(fetched.title, "Sunset")
        XCTAssertEqual(fetched.edit.brightness, 0.3, accuracy: 0.001)
        XCTAssertEqual(fetched.artworkFileName, fileName)
    }

    func testRenameUpdatesPayloadAndRow() async throws {
        let fileName = try await importArtwork()
        let design = CardDesign(title: "Before", artworkFileName: fileName)
        try await store.saveCardDesign(design)
        try await store.rename(id: design.id, title: "After")
        let fetched = try await store.cardDesign(id: design.id)
        XCTAssertEqual(fetched.title, "After")
    }

    func testDuplicateCopiesDesignAndMedia() async throws {
        let fileName = try await importArtwork()
        let design = CardDesign(title: "Original", artworkFileName: fileName)
        try await store.saveCardDesign(design)

        let copy = try await store.duplicate(id: design.id)
        XCTAssertNotEqual(copy.id, design.id)
        XCTAssertEqual(copy.title, "Original Copy")
        let copyDesign = try XCTUnwrap(copy.cardDesign)
        XCTAssertNotEqual(copyDesign.artworkFileName, fileName)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.paths.files.appendingPathComponent(copyDesign.artworkFileName).path))
        // Original untouched.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.paths.files.appendingPathComponent(fileName).path))
    }

    func testDeleteRemovesRowAndMedia() async throws {
        let fileName = try await importArtwork()
        let design = CardDesign(title: "Gone", artworkFileName: fileName)
        try await store.saveCardDesign(design)
        try await store.delete(id: design.id)

        await XCTAssertThrowsErrorAsync(try await store.cardDesign(id: design.id))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.paths.files.appendingPathComponent(fileName).path))
    }

    // MARK: - Organisation

    func testTagsSearchAndFavorites() async throws {
        let fileName = try await importArtwork()
        let design = CardDesign(title: "Taggable", artworkFileName: fileName)
        try await store.saveCardDesign(design)
        try await store.addTag(id: design.id, tag: "mono")
        try await store.addTag(id: design.id, tag: "gradient")
        try await store.setFavorite(id: design.id, true)

        let tagged = try await store.search("mono")
        XCTAssertEqual(tagged.count, 1)
        let maybeEntry = try await store.entry(id: design.id)
        let entry = try XCTUnwrap(maybeEntry)
        XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(Set(entry.tags), ["mono", "gradient"])

        try await store.removeTag(id: design.id, tag: "mono")
        let maybeAfter = try await store.entry(id: design.id)
        let after = try XCTUnwrap(maybeAfter)
        XCTAssertEqual(after.tags, ["gradient"])
    }

    func testCollections() async throws {
        let fileName = try await importArtwork()
        let design = CardDesign(title: "Grouped", artworkFileName: fileName)
        try await store.saveCardDesign(design)
        let collection = try await store.createCollection(name: "Dark Cards", kind: .card)
        try await store.setCollection(id: design.id, collection: collection.id)

        let maybeEntry = try await store.entry(id: design.id)
        let entry = try XCTUnwrap(maybeEntry)
        XCTAssertEqual(entry.collectionID, collection.id)
        let collections = try await store.collections()
        XCTAssertEqual(collections.first?.name, "Dark Cards")
    }

    func testRecentImportsRecorded() async throws {
        _ = try await importArtwork(named: "first.png")
        _ = try await importArtwork(named: "second.png")
        let recent = try await store.recentImports()
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first?.originalName, "second.png")
    }

    // MARK: - Bundle export / import

    func testBundleRoundTrip() async throws {
        let fileName = try await importArtwork()
        var design = CardDesign(title: "Portable", artworkFileName: fileName)
        design.edit.zoom = 1.7
        try await store.saveCardDesign(design)

        let data = try await store.exportBundle(id: design.id)
        XCTAssertGreaterThan(data.count, 1000)

        // Import into a *fresh* library to prove portability.
        let root2 = TestHelpers.tempLibraryRoot()
        let store2 = try LibraryStore(paths: LibraryPaths(root: root2))
        defer { try? FileManager.default.removeItem(at: root2) }

        let imported = try await store2.importBundle(data: data)
        let importedDesign = try XCTUnwrap(imported.cardDesign)
        XCTAssertEqual(importedDesign.title, "Portable")
        XCTAssertEqual(importedDesign.edit.zoom, 1.7, accuracy: 0.001)
        XCTAssertNotEqual(importedDesign.id, design.id, "imports mint a fresh id")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store2.paths.files.appendingPathComponent(importedDesign.artworkFileName).path))
    }

    func testBundleRejectsFutureVersion() async throws {
        var bundle = DesignBundle(
            formatVersion: 999, kind: .card,
            design: try JSONEncoder().encode(CardDesign(title: "x", artworkFileName: "x.png")),
            mediaFileName: "x.png", mediaData: Data([1]))
        bundle.formatVersion = 999
        let data = try JSONEncoder().encode(bundle)
        await XCTAssertThrowsErrorAsync(try await store.importBundle(data: data)) { error in
            XCTAssertEqual(error as? LibraryError, .unsupportedBundleVersion(999))
        }
    }

    // MARK: - Persistence across launches

    func testPersistenceAcrossReopen() async throws {
        let fileName = try await importArtwork()
        let design = CardDesign(title: "Persistent", artworkFileName: fileName)
        try await store.saveCardDesign(design)

        // Reopen the same root as a new store instance.
        let reopened = try LibraryStore(paths: LibraryPaths(root: root))
        let fetched = try await reopened.cardDesign(id: design.id)
        XCTAssertEqual(fetched.title, "Persistent")
    }
}

/// Async variant of XCTAssertThrowsError for actor calls.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown. \(message)")
    } catch {
        errorHandler(error)
    }
}
