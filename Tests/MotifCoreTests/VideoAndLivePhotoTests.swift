import XCTest
import AVFoundation
@testable import MotifCore

final class VideoAndLivePhotoTests: XCTestCase {

    private var tempDir: URL!
    private var videoURL: URL!
    private let processor = VideoProcessor()
    private let generator = LivePhotoGenerator()

    override func setUp() async throws {
        tempDir = TestHelpers.tempLibraryRoot()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        videoURL = tempDir.appendingPathComponent("source.mov")
        try await TestHelpers.makeTestVideo(at: videoURL, duration: 2.0, fps: 30)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Import / inspect

    func testVideoInspection() async throws {
        let info = try await processor.inspect(videoURL)
        XCTAssertEqual(info.duration, 2.0, accuracy: 0.2)
        XCTAssertEqual(info.dimensions.width, 320, accuracy: 1)
        XCTAssertEqual(info.dimensions.height, 240, accuracy: 1)
    }

    func testInspectRejectsBrokenVideo() async throws {
        let bad = tempDir.appendingPathComponent("bad.mov")
        try Data("not a video at all, but enough bytes".utf8).write(to: bad)
        await XCTAssertThrowsErrorAsync(try await processor.inspect(bad))
    }

    // MARK: - Trim / speed composition

    func testTrimAndSpeedProduceExpectedDuration() async throws {
        let asset = AVURLAsset(url: videoURL)
        var params = VideoEditParameters()
        params.trimStart = 0.5
        params.trimEnd = 1.5
        params.speed = 2.0
        let edited = try await processor.makeEditedComposition(asset: asset, params: params)
        XCTAssertEqual(edited.outputDuration, 0.5, accuracy: 0.1,
                       "1s of source at 2× should output ~0.5s")
    }

    func testTrimClampsToAssetDuration() async throws {
        let asset = AVURLAsset(url: videoURL)
        var params = VideoEditParameters()
        params.trimStart = 0
        params.trimEnd = 99 // beyond the 2s source
        let edited = try await processor.makeEditedComposition(asset: asset, params: params)
        XCTAssertEqual(edited.outputDuration, 2.0, accuracy: 0.2)
    }

    func testStillTimeMapsToOutputTimeline() async throws {
        let asset = AVURLAsset(url: videoURL)
        var params = VideoEditParameters()
        params.trimStart = 1.0
        params.trimEnd = 2.0
        params.stillTime = 1.4
        params.speed = 2.0
        let edited = try await processor.makeEditedComposition(asset: asset, params: params)
        XCTAssertEqual(edited.stillOutputTime, 0.2, accuracy: 0.05)
    }

    // MARK: - Export

    func testExportProducesVideoAtPresetSize() async throws {
        let asset = AVURLAsset(url: videoURL)
        var params = VideoEditParameters()
        params.trimStart = 0
        params.trimEnd = 0.5
        params.presetID = DisplayPreset.iPhone14Plus.id
        let edited = try await processor.makeEditedComposition(asset: asset, params: params)

        let out = tempDir.appendingPathComponent("exported.mov")
        try await processor.export(edited: edited, to: out, quality: .high)

        let exported = AVURLAsset(url: out)
        let tracks = try await exported.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 1284, accuracy: 4)
        XCTAssertEqual(size.height, 2778, accuracy: 4)
        let duration = try await exported.load(.duration)
        XCTAssertEqual(duration.seconds, 0.5, accuracy: 0.3)
    }

    func testRenderedStillMatchesPresetSize() async throws {
        let asset = AVURLAsset(url: videoURL)
        var params = VideoEditParameters()
        params.trimEnd = 0.5
        params.presetID = DisplayPreset.iPhoneSE.id
        let edited = try await processor.makeEditedComposition(asset: asset, params: params)
        let still = try await processor.renderedStill(from: edited)
        XCTAssertEqual(still.width, 750, accuracy: 4)
        XCTAssertEqual(still.height, 1334, accuracy: 4)
    }

    // MARK: - Live Photo generation

    func testGeneratedPairPassesStructuralValidation() async throws {
        var params = VideoEditParameters()
        params.trimStart = 0
        params.trimEnd = 1.0
        params.presetID = DisplayPreset.iPhoneSE.id  // small = fast render
        let pair = try await generator.generate(
            source: videoURL, params: params, quality: .low,
            outputDirectory: tempDir.appendingPathComponent("pair"))

        let validation = await generator.validate(pair)
        XCTAssertTrue(validation.stillHasIdentifier, "still JPEG should carry maker-note id")
        XCTAssertTrue(validation.videoHasIdentifier, "video should carry content identifier")
        XCTAssertTrue(validation.hasTimedMetadataTrack, "video should carry still-image-time track")
        XCTAssertTrue(validation.isStructurallyValid)
        XCTAssertGreaterThan(validation.videoDurationSeconds, 0.5)
    }

    func testValidationRejectsMismatchedPair() async throws {
        var params = VideoEditParameters()
        params.trimEnd = 0.5
        params.presetID = DisplayPreset.iPhoneSE.id
        let pair = try await generator.generate(
            source: videoURL, params: params, quality: .low,
            outputDirectory: tempDir.appendingPathComponent("pair"))

        // Lie about the identifier — validation must catch it.
        let bogus = LivePhotoPair(stillURL: pair.stillURL, videoURL: pair.videoURL,
                                  assetIdentifier: UUID().uuidString)
        let validation = await generator.validate(bogus)
        XCTAssertFalse(validation.isStructurallyValid)
    }

    // MARK: - Live Photo still metadata directly

    func testStillJPEGCarriesPairingIdentifier() async throws {
        var params = VideoEditParameters()
        params.trimEnd = 0.5
        params.presetID = DisplayPreset.iPhoneSE.id
        let asset = AVURLAsset(url: videoURL)
        let edited = try await processor.makeEditedComposition(asset: asset, params: params)
        let still = try await processor.renderedStill(from: edited)
        XCTAssertGreaterThan(still.width, 100)
    }
}
