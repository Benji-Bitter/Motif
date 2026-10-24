import SwiftUI
import MotifCore

/// Device management: detected devices, connection states, host tooling
/// status, diagnostics log, and the labelled simulated-device mode.
struct DevicesView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Motif.Metrics.gap * 1.5) {
                toolchainPanel
                devicesPanel
                if env.deviceManager.useSimulatedDevices {
                    simulatedPanel
                }
                diagnosticsPanel
            }
            .padding(24)
        }
        .navigationTitle("Devices")
    }

    // MARK: - Toolchain

    private var toolchainPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Detection service",
                              subtitle: env.deviceManager.serviceName)
                Spacer()
                StatusBadge(
                    env.deviceManager.serviceAvailable ? "Available" : "Not installed",
                    color: env.deviceManager.serviceAvailable ? Motif.Colors.ok : Motif.Colors.warn)
                Button { env.deviceManager.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            if let reason = env.deviceManager.serviceUnavailabilityReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("brew install libimobiledevice")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install libimobiledevice", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .help("Copy command")
                }
            }
        }
        .panel()
    }

    // MARK: - Devices

    private var devicesPanel: some View {
        VStack(alignment: .leading, spacing: Motif.Metrics.gap) {
            SectionHeader(title: "Connected devices")
            if env.deviceManager.devices.isEmpty {
                Text("No iPhone detected. Connect over USB, unlock the phone, and tap Trust when prompted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(env.deviceManager.devices) { device in
                    DeviceRow(device: device)
                }
            }
        }
        .panel()
    }

    private struct DeviceRow: View {
        @EnvironmentObject private var env: AppEnvironment
        let device: DeviceInfo

        var body: some View {
            HStack(spacing: 14) {
                DeviceIcon()
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(device.name).font(.headline)
                        if device.isSimulated {
                            StatusBadge("SIMULATED", color: Motif.Colors.warn)
                        }
                    }
                    Text("\(device.modelName) · iOS \(device.iosVersion.isEmpty ? "—" : device.iosVersion)"
                         + (device.buildVersion.map { " (\($0))" } ?? ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Identifier is held in memory only — never stored.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    stateBadge
                    Text(device.transport == .usb ? "USB" : "Network")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }

        private var stateBadge: StatusBadge {
            switch device.connectionState {
            case .ready: return StatusBadge("Ready", color: Motif.Colors.ok)
            case .needsUnlock: return StatusBadge("Unlock iPhone", color: Motif.Colors.warn)
            case .needsTrust: return StatusBadge("Needs trust", color: Motif.Colors.warn)
            case .connecting: return StatusBadge("Connecting", color: .secondary)
            case .failed: return StatusBadge("Failed", color: Motif.Colors.bad)
            case .disconnected: return StatusBadge("Disconnected", color: .secondary)
            }
        }
    }

    // MARK: - Simulated (development)

    private var simulatedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Simulated device — development only",
                          subtitle: "Clearly-labelled fake device used for UI work; nothing real is reported")
            Picker("Scenario", selection: scenarioBinding) {
                ForEach(SimulatedDeviceService.Scenario.allCases, id: \.self) { scenario in
                    Text(scenario.label).tag(scenario)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 280)
        }
        .panel()
    }

    private var scenarioBinding: Binding<SimulatedDeviceService.Scenario> {
        Binding(
            get: { .ready },
            set: { env.deviceManager.simulatedService.setScenario($0) })
    }

    // MARK: - Diagnostics

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Diagnostics")
                Spacer()
                Button {
                    let text = env.deviceManager.diagnostics
                        .map { "[\($0.level.rawValue)] \($0.timestamp): \($0.message)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }
            if env.deviceManager.diagnostics.isEmpty {
                Text("No diagnostics yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(env.deviceManager.diagnostics) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(levelColor(entry.level))
                                    .frame(width: 6, height: 6)
                                Text(entry.timestamp, style: .time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
        .panel()
    }

    private func levelColor(_ level: DiagnosticsEntry.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return Motif.Colors.warn
        case .error: return Motif.Colors.bad
        }
    }
}
