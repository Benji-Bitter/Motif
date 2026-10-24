import SwiftUI
import MotifCore

/// Settings: appearance, library location, device tooling, privacy statement,
/// the labelled development toggle, and about info.
struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Motif.Metrics.gap * 1.5) {

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Appearance")
                    Picker("Appearance", selection: $env.appearance) {
                        Text("System").tag(AppearanceMode.system)
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }
                .panel()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Library location",
                                  subtitle: env.store.paths.root.path)
                    HStack {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([env.store.paths.root])
                        }
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(env.store.paths.root.path, forType: .string)
                        }
                    }
                    Text("Originals are kept until you delete a design. Thumbnails are generated automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .panel()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Device detection")
                    HStack {
                        StatusBadge(
                            env.deviceManager.serviceAvailable ? "Available" : "Not installed",
                            color: env.deviceManager.serviceAvailable ? Motif.Colors.ok : Motif.Colors.warn)
                        Text(env.deviceManager.serviceName)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !env.deviceManager.serviceAvailable {
                        Text("Install the open-source libimobiledevice tools for USB device discovery:")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("brew install libimobiledevice")
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Divider().opacity(0.4)
                    Toggle(isOn: $env.useSimulatedDevices) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Simulated device mode")
                                StatusBadge("DEVELOPMENT", color: Motif.Colors.warn)
                            }
                            Text("Shows a fake iPhone for UI testing. Never used silently.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .panel()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Privacy")
                    Label("No accounts, no telemetry, no ads.", systemImage: "checkmark.shield")
                    Label("All image and video processing happens on this Mac.", systemImage: "checkmark.shield")
                    Label("Motif never reads card numbers, bank credentials, or Apple account passwords.", systemImage: "checkmark.shield")
                    Label("Device identifiers stay in memory for the session only.", systemImage: "checkmark.shield")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .panel()

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "About")
                    Text("Motif 0.1.0 — open source (MIT).")
                        .font(.callout)
                    Text("github.com/Benji-Bitter/Motif")
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .panel()
            }
            .padding(24)
        }
        .navigationTitle("Settings")
    }
}
