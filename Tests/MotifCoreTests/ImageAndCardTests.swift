import XCTest
import CoreGraphics
@testable import MotifCore

final class ImageAndCardTests: XCTestCase {

    private var tempDir: URL!
    private let processor = ImageProcessor()

    override func setUpWithError() throws {
        tempDir = TestHelpers.tempLibraryRoot()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Import validation

    func testImageImportValidationAcceptsRealPNG() throws {
        let url = tempDir.appendingPathComponent("ok.png")
        try TestHelpers.writePNG(TestHelpers.makeTestImage(), to: url)
        XCTAssertNoThrow(try ImportValidator.validateImageFile(url))
    }

    func testImageImportValidationRejectsNonImageBytes() throws {
        let url = tempDir.appendingPathComponent("fake.png")
        try Data("definitely not an image".utf8).write(to: url)
        XCTAssertThrowsError(try ImportValidator.validateImageFile(url)) { error in
            XCTAssertEqual(error as? FileError, .invalidImageData)
        }
    }

    func testImageImportValidationRejectsUnsupportedExtension() throws {
        let url = tempDir.appendingPathComponent("ok.bmp")
        try TestHelpers.writePNG(TestHelpers.makeTestImage(), to: url)
        XCTAssertThrowsError(try ImportValidator.validateImageFile(url)) { error in
            XCTAssertEqual(error as? FileError, .unsupportedType("bmp"))
        }
    }

    func testVideoValidationRejectsEmptyFile() throws {
        let url = tempDir.appendingPathComponent("empty.mov")
        try Data().write(to: url)
        XCTAssertThrowsError(try ImportValidator.validateVideoFile(url))
    }

    // MARK: - Filters & loading

    func testBrightnessAdjustmentChangesPixels() throws {
        let url = tempDir.appendingPathComponent("src.png")
        try TestHelpers.writePNG(TestHelpers.makeTestImage(base: (100, 100, 100), block: nil), to: url)
        let image = try processor.loadCIImage(from: url)

        var params = CardEditParameters()
        params.brightness = 0.8
        let filtered = processor.filtered(image, params: params)
        let rendered = try processor.render(filtered, extent: image.extent)

        let pixel = TestHelpers.pixel(rendered, x: 5, y: 5)
        XCTAssertNotNil(pixel)
        // sRGB output — red channel should be clearly lifted above the base 100.
        XCTAssertGreaterThan(Int(pixel!.0), 120)
    }

    func testThumbnailRespectsMaxPixelSize() throws {
        let url = tempDir.appendingPathComponent("big.png")
        try TestHelpers.writePNG(
            TestHelpers.makeTestImage(size: CGSize(width: 2000, height: 1000)), to: url)
        let thumb = try XCTUnwrap(processor.thumbnail(of: url, maxPixelSize: 128))
        XCTAssertLessThanOrEqual(max(thumb.width, thumb.height), 128)
    }

    // MARK: - Card rendering

    func testCardRenderProducesExactPresetSize() throws {
        let url = tempDir.appendingPathComponent("src.png")
        try TestHelpers.writePNG(
            TestHelpers.makeTestImage(size: CGSize(width: 1600, height: 1200)), to: url)
        let image = try processor.loadCIImage(from: url)

        let rendered = try CardArtworkRenderer.render(
            source: image, params: .default,
            outputSize: CardExportPreset.standard.pixelSize, processor: processor)
        XCTAssertEqual(rendered.width, 1536)
        XCTAssertEqual(rendered.height, 969)
    }

    func testCardRenderWritesPNGFile() throws {
        let url = tempDir.appendingPathComponent("src.png")
        try TestHelpers.writePNG(TestHelpers.makeTestImage(), to: url)
        let image = try processor.loadCIImage(from: url)
        let rendered = try CardArtworkRenderer.render(
            source: image, params: .default,
            outputSize: CardExportPreset.compact.pixelSize, processor: processor)
        let out = tempDir.appendingPathComponent("card.png")
        try processor.writePNG(rendered, to: out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        // Re-decode to prove it's a real PNG.
        XCTAssertNoThrow(try ImportValidator.validateImageFile(out))
    }

    func testPannedRenderDiffersFromCentered() throws {
        let url = tempDir.appendingPathComponent("src.png")
        try TestHelpers.writePNG(
            TestHelpers.makeTestImage(size: CGSize(width: 800, height: 600),
                                      base: (255, 0, 0), block: (0, 0, 255)),
            to: url)
        let image = try processor.loadCIImage(from: url)
        let centered = try CardArtworkRenderer.renderPreview(
            source: image, params: .default, maxPixelWidth: 300, processor: processor)
        var params = CardEditParameters(); params.offsetX = 0.45
        let panned = try CardArtworkRenderer.renderPreview(
            source: image, params: params, maxPixelWidth: 300, processor: processor)

        // Sample a corner pixel: with a heavy pan the blue block must move away.
        let a = TestHelpers.pixel(centered, x: centered.width / 2, y: centered.height / 2)
        let b = TestHelpers.pixel(panned, x: panned.width / 2, y: panned.height / 2)
        XCTAssertNotNil(a); XCTAssertNotNil(b)
        XCTAssertNotEqual(a!.0, b!.0, "panned render should differ at the sample point")
    }
}
