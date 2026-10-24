import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Errors surfaced by import validation and file management.
public enum FileError: Error, Equatable, Sendable {
    case unreadableFile(String)
    case unsupportedType(String)
    case invalidImageData
    case invalidVideoData
    case fileTooLarge(Int64)
    case copyFailed(String)
}

/// Standard locations inside the Motif library folder. Everything the app
/// persists lives under a single root that defaults to
/// `~/Library/Application Support/Motif` and is injected in tests.
public struct LibraryPaths: Sendable {
    public let root: URL
    public var files: URL { root.appendingPathComponent("Files", isDirectory: true) }
    public var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    public var exports: URL { root.appendingPathComponent("Exports", isDirectory: true) }
    public var temporary: URL { root.appendingPathComponent("Tmp", isDirectory: true) }
    public var database: URL { root.appendingPathComponent("library.sqlite") }

    public init(root: URL) {
        self.root = root
    }

    /// Default per-user library location.
    public static func `default`() -> LibraryPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return LibraryPaths(root: base.appendingPathComponent("Motif", isDirectory: true))
    }

    public func ensureExists() throws {
        for dir in [root, files, thumbnails, exports, temporary] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Atomic file writing: Foundation writes to a sibling temp file first and
/// renames it into place so readers never observe a half-written file.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

/// Validates imported media before it enters the library. Checks the declared
/// type *and* probes the bytes — a renamed file is not a valid image.
public enum ImportValidator {
    public static let imageTypes: [UTType] = [.png, .jpeg, .heic]
    public static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie]
    /// Live Photo stills may additionally arrive as HEIC/JPEG; handled by imageTypes.
    public static let maxImportBytes: Int64 = 4 * 1024 * 1024 * 1024  // 4 GB hard cap

    public static func validateImageFile(_ url: URL) throws -> UTType {
        guard let type = UTType(filenameExtension: url.pathExtension),
              imageTypes.contains(type) else {
            throw FileError.unsupportedType(url.pathExtension)
        }
        try validateSize(url)
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw FileError.invalidImageData
        }
        return type
    }

    public static func validateVideoFile(_ url: URL) throws -> UTType {
        guard let type = UTType(filenameExtension: url.pathExtension),
              videoTypes.contains(type) else {
            throw FileError.unsupportedType(url.pathExtension)
        }
        try validateSize(url)
        // Byte-level probe: AVAsset performs deeper validation on open; here we
        // at least require a non-empty readable file.
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw FileError.unreadableFile(url.lastPathComponent)
        }
        defer { try? handle.close() }
        guard (try? handle.read(upToCount: 12))?.count ?? 0 >= 8 else {
            throw FileError.invalidVideoData
        }
        return type
    }

    private static func validateSize(_ url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size > maxImportBytes { throw FileError.fileTooLarge(size) }
        if size == 0 { throw FileError.unreadableFile(url.lastPathComponent) }
    }

    /// Generates a stable stored file name for imported media.
    public static func storedFileName(for id: UUID, original url: URL) -> String {
        "\(id.uuidString).\(url.pathExtension.lowercased())"
    }
}

/// SHA-256 helper used for catalogue checksums and export manifests.
public enum Checksum {
    public static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return sha256(of: data)
    }

    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
