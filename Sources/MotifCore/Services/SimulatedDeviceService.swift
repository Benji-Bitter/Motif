import Foundation
import os

/// A controllable fake device source used for development UI work and tests.
/// Devices produced here are always flagged `isSimulated` and the UI must
/// label them. It never stands in for the real service silently — the app
/// only uses it when the user explicitly enables simulated-device mode.
public final class SimulatedDeviceService: DeviceService, @unchecked Sendable {
    public let displayName = "Simulated devices (development)"

    public enum Scenario: String, Sendable, CaseIterable {
        case none
        case ready
        case locked
        case untrusted

        public var label: String {
            switch self {
            case .none: return "No device"
            case .ready: return "Connected & trusted"
            case .locked: return "Connected & locked"
            case .untrusted: return "Connected & untrusted"
            }
        }
    }

    private struct State: Sendable {
        var scenario: Scenario = .ready
        var continuations: [UUID: AsyncStream<[DeviceInfo]>.Continuation] = [:]
        var logEntries: [DiagnosticsEntry] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(scenario: Scenario = .ready) {
        state.withLock { $0.scenario = scenario }
    }

    public var isAvailable: Bool { true }
    public var unavailabilityReason: String? { nil }

    public func setScenario(_ scenario: Scenario) {
        let targets = state.withLock { s -> [AsyncStream<[DeviceInfo]>.Continuation] in
            s.scenario = scenario
            s.logEntries.append(DiagnosticsEntry(level: .info, message: "Simulated scenario → \(scenario.rawValue)"))
            return Array(s.continuations.values)
        }
        let devices = currentDevices(scenario: scenario)
        for continuation in targets { continuation.yield(devices) }
    }

    public func observeDevices() -> AsyncStream<[DeviceInfo]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[DeviceInfo]>.makeStream()
        let scenario = state.withLock { s -> Scenario in
            s.continuations[id] = continuation
            return s.scenario
        }
        continuation.yield(currentDevices(scenario: scenario))
        continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(id)
        }
        return stream
    }

    public func refresh() async {
        let (scenario, targets) = state.withLock { s in
            (s.scenario, Array(s.continuations.values))
        }
        let devices = currentDevices(scenario: scenario)
        for continuation in targets { continuation.yield(devices) }
    }

    public func diagnostics() -> [DiagnosticsEntry] {
        state.withLock { $0.logEntries }
    }

    // MARK: - Internals

    private func currentDevices(scenario: Scenario) -> [DeviceInfo] {
        switch scenario {
        case .none:
            return []
        case .ready:
            return [simulated(state: .ready, trust: .trusted)]
        case .locked:
            return [simulated(state: .needsUnlock, trust: .locked)]
        case .untrusted:
            return [simulated(state: .needsTrust, trust: .untrusted)]
        }
    }

    private func simulated(state: DeviceConnectionState, trust: TrustState) -> DeviceInfo {
        DeviceInfo(
            id: "SIM-0000-0001",
            name: "Simulated iPhone",
            productType: "iPhone14,8",
            modelName: "iPhone 14 Plus",
            iosVersion: "17.5.1",
            buildVersion: "21F90",
            transport: .usb,
            trustState: trust,
            connectionState: state,
            isSimulated: true
        )
    }

    private func removeContinuation(_ id: UUID) {
        state.withLock { $0.continuations[id] = nil }
    }
}
