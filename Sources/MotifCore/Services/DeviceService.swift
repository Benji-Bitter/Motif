import Foundation
import os

/// Abstraction over "is an iPhone attached, and what can we know about it".
/// Implementations never fabricate access: if the host tooling or the device
/// pairing state doesn't allow an operation, they say so.
public protocol DeviceService: Sendable {
    var displayName: String { get }
    /// Whether the backing mechanism can run at all on this machine.
    var isAvailable: Bool { get }
    var unavailabilityReason: String? { get }

    /// Continuous device list; emits whenever the set or per-device state changes.
    func observeDevices() -> AsyncStream<[DeviceInfo]>
    /// Forces a re-poll.
    func refresh() async
    /// Best-effort diagnostics accumulated by the service.
    func diagnostics() -> [DiagnosticsEntry]
}

/// Runs short-lived command line tools with a timeout. Used by
/// `LibimobiledeviceCLIService`; never launches arbitrary user input.
public struct ProcessRunner: Sendable {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
    }

    public init() {}

    public func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 10) -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do { try process.run() } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        var timedOut = false
        if group.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
        }
        let stdout = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return Result(status: timedOut ? -2 : process.terminationStatus,
                      stdout: stdout, stderr: stderr)
    }
}

/// Locates the libimobiledevice command-line tools. These are the standard,
/// legitimate interface for host↔device pairing and basic information —
/// the same tooling Finder uses under different wrappers.
public struct DeviceToolchain: Sendable {
    public var ideviceID: URL
    public var ideviceinfo: URL
    public var idevicepair: URL?

    static let candidateDirs = [
        "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
        "/usr/bin", "/bin"
    ]

    public static func locate(fileManager: FileManager = .default) -> DeviceToolchain? {
        func find(_ name: String) -> URL? {
            for dir in candidateDirs {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: url.path) { return url }
            }
            // Fall back to PATH lookup.
            let runner = ProcessRunner()
            let result = runner.run(URL(fileURLWithPath: "/usr/bin/which"), [name], timeout: 5)
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0, !path.isEmpty,
                  fileManager.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        guard let ideviceID = find("idevice_id"),
              let ideviceinfo = find("ideviceinfo") else { return nil }
        return DeviceToolchain(ideviceID: ideviceID, ideviceinfo: ideviceinfo,
                               idevicepair: find("idevicepair"))
    }
}

/// Device service backed by the libimobiledevice tools (`idevice_id`,
/// `ideviceinfo`, `idevicepair`). Discovers devices by polling — the CLI tools
/// expose no event interface — and derives trust state from pairing output.
///
/// If the tools aren't installed (`brew install libimobiledevice`) the service
/// reports itself unavailable instead of pretending devices don't exist.
public final class LibimobiledeviceCLIService: DeviceService, @unchecked Sendable {
    public let displayName = "libimobiledevice"

    private struct State: Sendable {
        var continuations: [UUID: AsyncStream<[DeviceInfo]>.Continuation] = [:]
        var logEntries: [DiagnosticsEntry] = []
        var lastDevices: [DeviceInfo] = []
        var polling = false
    }

    private let toolchain: DeviceToolchain?
    private let runner = ProcessRunner()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var pollTask: Task<Void, Never>?

    public init(toolchain: DeviceToolchain? = DeviceToolchain.locate()) {
        self.toolchain = toolchain
        if toolchain == nil {
            append(.warning, "libimobiledevice tools not found. Install with `brew install libimobiledevice` to enable device detection.")
        }
    }

    public var isAvailable: Bool { toolchain != nil }

    public var unavailabilityReason: String? {
        toolchain == nil
            ? "libimobiledevice is not installed. Install it with `brew install libimobiledevice`, then reconnect the iPhone."
            : nil
    }

    public func observeDevices() -> AsyncStream<[DeviceInfo]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[DeviceInfo]>.makeStream()
        let snapshot = state.withLock { s in
            s.continuations[id] = continuation
            return s.lastDevices
        }
        continuation.yield(snapshot)
        startPollingIfNeeded()
        continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(id)
        }
        return stream
    }

    public func refresh() async {
        await pollAndBroadcast()
    }

    public func diagnostics() -> [DiagnosticsEntry] {
        state.withLock { $0.logEntries }
    }

    // MARK: - Internals

    private func startPollingIfNeeded() {
        let shouldStart = state.withLock { s -> Bool in
            if s.polling { return false }
            s.polling = true
            return true
        }
        guard shouldStart, toolchain != nil else { return }

        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let keepPolling = self.state.withLock { $0.polling }
                guard keepPolling else { return }
                await self.pollAndBroadcast()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    private func pollAndBroadcast() async {
        guard let toolchain else { return }
        let devices = await pollDevices(toolchain: toolchain)
        let targets = state.withLock { s -> [AsyncStream<[DeviceInfo]>.Continuation] in
            guard devices != s.lastDevices else { return [] }
            s.lastDevices = devices
            return Array(s.continuations.values)
        }
        for continuation in targets { continuation.yield(devices) }
    }

    private func pollDevices(toolchain: DeviceToolchain) async -> [DeviceInfo] {
        let result = runner.run(toolchain.ideviceID, ["-l"], timeout: 8)
        guard result.status == 0 else {
            append(.error, "idevice_id failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            return []
        }
        let udids = result.stdout.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var devices: [DeviceInfo] = []
        for udid in udids {
            devices.append(fetchInfo(udid: udid, toolchain: toolchain))
        }
        return devices
    }

    private func fetchInfo(udid: String, toolchain: DeviceToolchain) -> DeviceInfo {
        let result = runner.run(toolchain.ideviceinfo, ["-u", udid], timeout: 8)
        if result.status != 0 {
            let detail = (result.stderr + result.stdout).lowercased()
            if detail.contains("passwordprotected") || detail.contains("password protected") {
                return DeviceInfo(id: udid, name: "Locked iPhone", productType: "",
                                  modelName: "iPhone", iosVersion: "",
                                  trustState: .locked, connectionState: .needsUnlock)
            }
            if detail.contains("pairingdialog") || detail.contains("userdeniedpairing")
                || detail.contains("invalidhostid") || detail.contains("pair") {
                return DeviceInfo(id: udid, name: "Untrusted iPhone", productType: "",
                                  modelName: "iPhone", iosVersion: "",
                                  trustState: .untrusted, connectionState: .needsTrust)
            }
            return DeviceInfo(id: udid, name: "iPhone", productType: "",
                              modelName: "iPhone", iosVersion: "",
                              trustState: .unknown,
                              connectionState: .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        var fields: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        let productType = fields["ProductType"] ?? ""
        return DeviceInfo(
            id: udid,
            name: fields["DeviceName"] ?? "iPhone",
            productType: productType,
            modelName: DeviceModelCatalog.marketingName(for: productType),
            iosVersion: fields["ProductVersion"] ?? "",
            buildVersion: fields["BuildVersion"],
            transport: .usb,
            trustState: .trusted,
            connectionState: .ready
        )
    }

    private func append(_ level: DiagnosticsEntry.Level, _ message: String) {
        state.withLock { s in
            s.logEntries.append(DiagnosticsEntry(level: level, message: message))
            if s.logEntries.count > 500 { s.logEntries.removeFirst(s.logEntries.count - 500) }
        }
        Log.device.debug("\(message)")
    }

    private func removeContinuation(_ id: UUID) {
        let empty = state.withLock { s -> Bool in
            s.continuations[id] = nil
            return s.continuations.isEmpty
        }
        if empty {
            state.withLock { $0.polling = false }
            pollTask?.cancel()
            pollTask = nil
        }
    }
}
