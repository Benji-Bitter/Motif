import XCTest
import CoreGraphics
@testable import MotifCore

final class GeometryAndHistoryTests: XCTestCase {

    // MARK: - Cover framing

    func testCoverFramingScalesToFillPortraitRenderSize() {
        // Landscape content into a portrait render: must scale by height.
        let t = CoverFraming.imageTransform(
            contentSize: CGSize(width: 1920, height: 1080),
            renderSize: CGSize(width: 1284, height: 2778),
            zoom: 1, offsetX: 0, offsetY: 0)
        // Corners of scaled content should cover the whole render rect.
        let rect = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080)).applying(t)
        XCTAssertLessThanOrEqual(rect.minX, 0)
        XCTAssertLessThanOrEqual(rect.minY, 0)
        XCTAssertGreaterThanOrEqual(rect.maxX, 1284)
        XCTAssertGreaterThanOrEqual(rect.maxY, 2778)
    }

    func testCoverFramingZoomScalesBeyondCover() {
        let base = CoverFraming.imageTransform(
            contentSize: CGSize(width: 100, height: 100),
            renderSize: CGSize(width: 200, height: 200),
            zoom: 1, offsetX: 0, offsetY: 0)
        let zoomed = CoverFraming.imageTransform(
            contentSize: CGSize(width: 100, height: 100),
            renderSize: CGSize(width: 200, height: 200),
            zoom: 2, offsetX: 0, offsetY: 0)
        XCTAssertEqual(base.a, 2, accuracy: 0.001)      // cover 2×
        XCTAssertEqual(zoomed.a, 4, accuracy: 0.001)    // cover × zoom
    }

    func testOffsetPanTranslatesContent() {
        let a = CoverFraming.imageTransform(
            contentSize: CGSize(width: 400, height: 400),
            renderSize: CGSize(width: 200, height: 200),
            zoom: 1, offsetX: 0.25, offsetY: -0.5)
        XCTAssertEqual(a.tx, 0.25 * 200 + (200 - 400 * 0.5) / 2, accuracy: 0.01)
    }

    // MARK: - Card artwork transform

    func testCardTransformKeepsCardAspectCoverage() {
        let t = CardArtworkRenderer.artworkTransform(
            imageExtent: CGRect(x: 0, y: 0, width: 2000, height: 1000),
            outputSize: CGSize(width: 1536, height: 969),
            params: .default)
        let rect = CGRect(x: 0, y: 0, width: 2000, height: 1000).applying(t)
        XCTAssertTrue(rect.contains(CGRect(x: 0, y: 0, width: 1536, height: 969)),
                      "cover-fit must fill the whole canvas")
    }

    func testCardRotationStillCoversCanvas() {
        var params = CardEditParameters()
        params.rotationDegrees = 45
        params.zoom = 2.5  // rotation needs extra zoom to keep corners covered
        let t = CardArtworkRenderer.artworkTransform(
            imageExtent: CGRect(x: 0, y: 0, width: 2000, height: 1000),
            outputSize: CGSize(width: 1536, height: 969),
            params: params)
        let rect = CGRect(x: 0, y: 0, width: 2000, height: 1000).applying(t)
        XCTAssertTrue(rect.contains(CGRect(x: 0, y: 0, width: 1536, height: 969)))
    }

    // MARK: - Edit history

    func testUndoRedoRoundTrip() {
        var history = EditHistory(CardEditParameters.default)
        var v = CardEditParameters()
        v.brightness = 0.5
        history.push(v)
        XCTAssertEqual(history.current.brightness, 0.5)
        XCTAssertTrue(history.canUndo)
        history.undo()
        XCTAssertEqual(history.current.brightness, 0)
        history.redo()
        XCTAssertEqual(history.current.brightness, 0.5)
    }

    func testPushClearsRedoStack() {
        var history = EditHistory(CardEditParameters.default)
        var v = CardEditParameters(); v.zoom = 2
        history.push(v)
        history.undo()
        var w = CardEditParameters(); w.zoom = 3
        history.push(w)
        XCTAssertFalse(history.canRedo)
    }

    func testGestureStrokeCollapsesToOneStep() {
        var history = EditHistory(CardEditParameters.default)
        history.beginStroke()
        for i in 1...10 {
            var v = history.current; v.zoom = 1 + Double(i) * 0.1
            history.updateInPlace(v)
        }
        history.endStroke()
        XCTAssertEqual(history.current.zoom, 2, accuracy: 0.001)
        history.undo()
        XCTAssertEqual(history.current.zoom, 1)
    }

    func testPushWithSameValueIsNoop() {
        var history = EditHistory(CardEditParameters.default)
        history.push(.default)
        XCTAssertFalse(history.canUndo)
    }

    // MARK: - Versions & presets

    func testSystemVersionParsingAndComparison() {
        XCTAssertEqual(SystemVersion("17.5.1"), SystemVersion(major: 17, minor: 5, patch: 1))
        XCTAssertTrue(SystemVersion("16.1")! < SystemVersion("17")!)
        XCTAssertTrue(SystemVersion("15.0")! >= SystemVersion(major: 15))
        XCTAssertNil(SystemVersion("not-a-version"))
    }

    func testPresetLookupForIPhone14Plus() {
        let preset = DisplayPreset.preset(forProductType: "iPhone14,8")
        XCTAssertEqual(preset?.id, "iphone-14-plus")
        XCTAssertEqual(preset?.pixelSize, CGSize(width: 1284, height: 2778))
    }

    func testModelCatalog() {
        XCTAssertEqual(DeviceModelCatalog.marketingName(for: "iPhone14,8"), "iPhone 14 Plus")
        XCTAssertTrue(DeviceModelCatalog.marketingName(for: "iPhone99,1").contains("iPhone99,1"),
                      "unknown models should show the raw product type, not a guess")
    }
}
