import XCTest
@testable import MotifCore

final class DeviceAndApplyTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = TestHelpers.tempLibraryRoot()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func device(ios: String, state: DeviceConnectionState = .ready) -> DeviceInfo {
        DeviceInfo(id: "TEST", name: "Test iPhone", productType: "iPhone14,8",
                   modelName: "iPhone 14 Plus", iosVersion: ios,
                   trustState: .trusted, connectionState: state)
    }

    // MARK: - Compatibility decisions

    func testCardArtworkIsNeverReportedSupported() {
        for ios in ["14.0", "15.5", "16.1.2", "17.5.1", "18.0", "26.0"] {
            let availability = CapabilityRegistry.availability(
                of: .cardArtworkReplacement, iOS: SystemVersion(ios))
            XCTAssertNotEqual(availability.status, .supported,
                              "card artwork must never be claimed supported (iOS \(ios))")
        }
    }

    func testCardArtworkExploitWindowMarkedNotTested() {
        let availability = CapabilityRegistry.availability(
            of: .cardArtworkReplacement, iOS: SystemVersion("16.0"))
        XCTAssertEqual(availability.status, .notTested)
        // Outside the window → unsupported.
        let ios17 = CapabilityRegistry.availability(
            of: .cardArtworkReplacement, iOS: SystemVersion("17.0"))
        XCTAssertEqual(ios17.status, .unsupported)
    }

    func testLivePhotoPlaybackSupportedOn17Plus() {
        XCTAssertEqual(CapabilityRegistry.availability(
            of: .livePhotoLockScreenPlayback, iOS: SystemVersion("17.0")).status, .supported)
        XCTAssertEqual(CapabilityRegistry.availability(
            of: .livePhotoLockScreenPlayback, iOS: SystemVersion("16.0")).status, .notTested)
    }

    func testTransferAlwaysRequiresManual() {
        XCTAssertEqual(CapabilityRegistry.availability(
            of: .livePhotoTransfer, iOS: SystemVersion("17.0")).status, .requiresManual)
    }

    // MARK: - Simulated device service

    func testSimulatedServiceReportsReadyDevice() async {
        let service = SimulatedDeviceService(scenario: .ready)
        var iterator = service.observeDevices().makeAsyncIterator()
        let devices = await iterator.next()
        XCTAssertEqual(devices?.count, 1)
        XCTAssertEqual(devices?.first?.connectionState, .ready)
        XCTAssertEqual(devices?.first?.isSimulated, true)
    }

    func testSimulatedServiceLockedDevice() async {
        let service = SimulatedDeviceService(scenario: .locked)
        var iterator = service.observeDevices().makeAsyncIterator()
        let devices = await iterator.next()
        XCTAssertEqual(devices?.first?.connectionState, .needsUnlock)
    }

    func testSimulatedScenarioChangeEmits() async {
        let service = SimulatedDeviceService(scenario: .none)
        var iterator = service.observeDevices().makeAsyncIterator()
        _ = await iterator.next()            // []
        service.setScenario(.ready)
        let updated = await iterator.next()
        XCTAssertEqual(updated?.first?.connectionState, .ready)
        service.setScenario(.none)
        let emptied = await iterator.next()
        XCTAssertEqual(emptied?.count, 0)
    }

    // MARK: - Apply engine planning

    func testPlanRequiresDevice() async {
        let engine = ApplyEngine()
        let context = ApplyContext(outputDirectory: tempDir)
        let plan = await engine.plan(for: context)
        let blockers = await engine.blockers(for: context, plan: plan)
        XCTAssertTrue(blockers.contains { $0.contains("Connect an iPhone") })
    }

    func testPlanMarksCardInstallUnsupported() async throws {
        let engine = ApplyEngine()
        let art = tempDir.appendingPathComponent("art.png")
        try TestHelpers.writePNG(TestHelpers.makeTestImage(), to: art)
        var context = ApplyContext(
            device: device(ios: "17.5.1"),
            cardDesign: CardDesign(title: "T", artworkFileName: "art.png"),
            cardArtworkSource: art,
            outputDirectory: tempDir)
        context.device = device(ios: "17.5.1")
        let plan = await engine.plan(for: context)
        let cardOp = try XCTUnwrap(plan.first { $0.kind == .cardSkinInstall })
        guard case .unsupported = cardOp.status else {
            return XCTFail("expected unsupported, got \(cardOp.status)")
        }
    }

    func testPlanForWallpaperListsExportAndManualTransfer() async throws {
        let engine = ApplyEngine()
        let video = tempDir.appendingPathComponent("v.mov")
        try await TestHelpers.makeTestVideo(at: video, duration: 1.0)
        let context = ApplyContext(
            device: device(ios: "17.5.1"),
            wallpaperDesign: WallpaperDesign(title: "W", sourceFileName: "v.mov",
                                             edit: VideoEditParameters(trimEnd: 0.5)),
            videoSource: video,
            outputDirectory: tempDir)
        let plan = await engine.plan(for: context)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.first { $0.kind == .livePhotoExport }?.status, .supported)
        guard case .requiresManual = try XCTUnwrap(
            plan.first { $0.kind == .livePhotoTransfer }?.status) else {
            return XCTFail("transfer must require manual install")
        }
    }

    // MARK: - Apply engine execution

    func testExecuteWallpaperEndToEnd() async throws {
        let engine = ApplyEngine()
        let video = tempDir.appendingPathComponent("v.mov")
        try await TestHelpers.makeTestVideo(at: video, duration: 1.0)
        var edit = VideoEditParameters(trimEnd: 0.5)
        edit.presetID = DisplayPreset.iPhoneSE.id
        let context = ApplyContext(
            device: device(ios: "17.5.1"),
            wallpaperDesign: WallpaperDesign(title: "W", sourceFileName: "v.mov", edit: edit),
            videoSource: video,
            outputDirectory: tempDir,
            exportQuality: .low)
        let plan = await engine.plan(for: context)
        let blockers = await engine.blockers(for: context, plan: plan)
        XCTAssertTrue(blockers.isEmpty)

        var finalStatuses: [OperationKind: OperationStatus] = [:]
        for try await op in await engine.execute(context: context, plan: plan) {
            if op.status.isTerminal { finalStatuses[op.kind] = op.status }
        }

        guard case .succeeded = finalStatuses[.livePhotoExport] else {
            return XCTFail("export should succeed, got \(String(describing: finalStatuses[.livePhotoExport]))")
        }
        guard case .requiresManual = finalStatuses[.livePhotoTransfer] else {
            return XCTFail("transfer must end as requiresManual")
        }
        // Instructions file should exist in the output directory.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("INSTALLATION.txt").path))
    }

    func testExecuteCardOperationReportsUnsupported() async throws {
        let engine = ApplyEngine()
        let art = tempDir.appendingPathComponent("art.png")
        try TestHelpers.writePNG(TestHelpers.makeTestImage(), to: art)
        let context = ApplyContext(
            device: device(ios: "17.5.1"),
            cardDesign: CardDesign(title: "T", artworkFileName: "art.png"),
            cardArtworkSource: art,
            outputDirectory: tempDir)
        let plan = await engine.plan(for: context)
        var last: ApplyOperation?
        for try await op in await engine.execute(context: context, plan: plan) {
            last = op
        }
        guard case .unsupported = last?.status else {
            return XCTFail("card op must end unsupported, got \(String(describing: last?.status))")
        }
    }

    // MARK: - Process runner

    func testProcessRunnerCapturesOutput() {
        let result = ProcessRunner().run(
            URL(fileURLWithPath: "/bin/echo"), ["hello"], timeout: 5)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testProcessRunnerTimesOut() {
        let result = ProcessRunner().run(
            URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 0.3)
        XCTAssertEqual(result.status, -2)
    }

    func testToolchainLocateMayBeAbsent() {
        // Don't assert presence/absence — just that locate() doesn't crash and
        // returns a coherent result.
        let toolchain = DeviceToolchain.locate()
        if let toolchain {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: toolchain.ideviceID.path))
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: toolchain.ideviceinfo.path))
        }
    }

    func testLibimobiledeviceServiceAvailability() {
        let service = LibimobiledeviceCLIService(toolchain: DeviceToolchain.locate())
        // When tools are missing the service must say so, not fake success.
        if !service.isAvailable {
            XCTAssertNotNil(service.unavailabilityReason)
        }
    }
}
