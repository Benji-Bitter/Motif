import Foundation
import Combine

/// UI-facing device state. Wraps a `DeviceService`, republishes the device
/// list, and accumulates diagnostics. Simulated devices are only ever used
/// when the user explicitly enables them — real detection is never shadowed.
@MainActor
public final class DeviceManager: ObservableObject {
    @Published public private(set) var devices: [DeviceInfo] = []
    @Published public var selectedDeviceID: String?
    @Published public private(set) var diagnostics: [DiagnosticsEntry] = []
    @Published public private(set) var serviceName: String = ""
    @Published public private(set) var serviceAvailable: Bool = false
    @Published public private(set) var serviceUnavailabilityReason: String? = nil
    /// Development toggle. When true, a clearly-labelled simulated iPhone is
    /// reported. Never enabled automatically.
    @Published public var useSimulatedDevices: Bool = false {
        didSet { restartObservation() }
    }

    private let realService: DeviceService
    public let simulatedService = SimulatedDeviceService()
    private var observationTask: Task<Void, Never>?
    private var activeService: DeviceService?

    public var selectedDevice: DeviceInfo? {
        devices.first { $0.id == selectedDeviceID } ?? devices.first
    }

    /// true when a device is connected, paired, and usable.
    public var hasReadyDevice: Bool {
        devices.contains { $0.connectionState == .ready }
    }

    public init(service: DeviceService? = nil) {
        self.realService = service ?? LibimobiledeviceCLIService()
    }

    deinit {
        observationTask?.cancel()
    }

    public func startObserving() {
        restartObservation()
    }

    public func refresh() {
        Task { await activeService?.refresh() }
    }

    private func restartObservation() {
        observationTask?.cancel()
        devices = []
        selectedDeviceID = nil

        let service: DeviceService = useSimulatedDevices ? simulatedService : realService
        activeService = service
        serviceName = service.displayName
        serviceAvailable = service.isAvailable
        serviceUnavailabilityReason = service.unavailabilityReason

        if !service.isAvailable, let reason = service.unavailabilityReason {
            diagnostics.append(DiagnosticsEntry(level: .warning, message: reason))
        }

        let stream = service.observeDevices()
        observationTask = Task { [weak self] in
            for await updated in stream {
                guard !Task.isCancelled else { return }
                self?.devices = updated
                if let selected = self?.selectedDeviceID,
                   !updated.contains(where: { $0.id == selected }) {
                    self?.selectedDeviceID = updated.first?.id
                }
            }
        }

        // Surface service diagnostics periodically.
        Task { [weak self, service] in
            while !Task.isCancelled {
                let entries = service.diagnostics()
                if entries != self?.diagnostics {
                    self?.diagnostics = entries
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
