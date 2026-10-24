import SwiftUI
import MotifCore
import UniformTypeIdentifiers

/// Landing surface: connected device summary, quick imports, recent designs,
/// and the honest per-feature compatibility table.
struct OverviewView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showArtworkImporter = false
    @State private var showVideoImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Motif.Metrics.gap * 1.5) {
                header
                devicePanel
                quickActions
                compatibilityPanel
                recentPanel
            }
            .padding(24)
        }
        .navigationTitle("Overview")
        .fileImporter(isPresented: $showArtworkImporter,
                      allowedContentTypes: [.png, .jpeg, .heic]) { result in
            if case .success(let url) = result {
                Task { await env.importArtwork(from: url) }
            }
        }
        .fileImporter(isPresented: $showVideoImporter,
                      allowedContentTypes: [.mpeg4Movie, .quickTimeMovie]) { result in
            if case .success(let url) = result {
                Task { await env.importVideo(from: url) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Make your iPhone yours.")
                .font(.title.weight(.semibold))
            Text("Design card artwork and live wallpapers locally — apply what's possible, export what isn't.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Device

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: Motif.Metrics.gap) {
            SectionHeader(title: "Connected iPhone")
            if let device = env.deviceManager.selectedDevice {
                HStack(spacing: 16) {
                    DeviceIcon()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(device.name).font(.headline)
                            if device.isSimulated {
                                StatusBadge("SIMULATED — development", color: .orange)
                            }
                        }
                        Text("\(device.modelName) · iOS \(device.iosVersion.isEmpty ? "unknown" : device.iosVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    connectionBadge(for: device)
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No iPhone detected")
                            .font(.headline)
                        Text(env.deviceManager.serviceUnavailabilityReason
                             ?? "Connect an iPhone over USB and unlock it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Devices") { env.selection = .devices }
                }
            }
        }
        .panel()
    }

    private func connectionBadge(for device: DeviceInfo) -> some View {
        switch device.connectionState {
        case .ready: return StatusBadge("Connected & trusted", color: Motif.Colors.ok)
        case .needsUnlock: return StatusBadge("Unlock the iPhone", color: Motif.Colors.warn)
        case .needsTrust: return StatusBadge("Trust this computer", color: Motif.Colors.warn)
        case .connecting: return StatusBadge("Connecting…", color: .secondary)
        case .failed(let why): return StatusBadge(why.isEmpty ? "Failed" : "Failed: \(why)", color: Motif.Colors.bad)
        case .disconnected: return StatusBadge("Disconnected", color: .secondary)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: Motif.Metrics.gap) {
            Button { showArtworkImporter = true } label: {
                Label("Import Card Artwork", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            Button { showVideoImporter = true } label: {
                Label("Import Video", systemImage: "film.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            Button { env.showingApply = true } label: {
                Label("Apply…", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .panel()
    }

    // MARK: - Compatibility

    private var compatibilityPanel: some View {
        VStack(alignment: .leading, spacing: Motif.Metrics.gap) {
            SectionHeader(title: "Compatibility",
                          subtitle: env.deviceManager.selectedDevice.map {
                              "iOS \($0.iosVersion) · \($0.modelName)"
                          } ?? "No device — showing general availability")
            ForEach(CapabilityRegistry.availability(for: env.deviceManager.selectedDevice)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(featureTitle(item.feature))
                        .font(.callout)
                        .frame(width: 240, alignment: .leading)
                    StatusBadge(item.status.label, color: badgeColor(item.status))
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if item.id != Feature.allCases.last {
                    Divider().opacity(0.4)
                }
            }
        }
        .panel()
    }

    private func featureTitle(_ feature: Feature) -> String {
        switch feature {
        case .cardArtworkReplacement: return "Card artwork replacement"
        case .livePhotoExport: return "Live Photo export"
        case .livePhotoLockScreenPlayback: return "Lock-screen animation"
        case .livePhotoTransfer: return "Wallpaper transfer"
        case .deviceDetection: return "Device detection"
        }
    }

    private func badgeColor(_ status: AvailabilityStatus) -> Color {
        switch status {
        case .supported: return Motif.Colors.ok
        case .requiresManual: return Motif.Colors.manual
        case .notTested: return Motif.Colors.warn
        case .unsupported: return Motif.Colors.bad
        }
    }

    // MARK: - Recent designs

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: Motif.Metrics.gap) {
            HStack {
                SectionHeader(title: "Recent designs")
                Spacer()
                Button("Open Library") { env.selection = .library }
                    .controlSize(.small)
            }
            if env.entries.isEmpty {
                Text("Nothing here yet — import artwork or a video to start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                    ForEach(env.entries.prefix(8)) { entry in
                        RecentCell(entry: entry)
                    }
                }
            }
        }
        .panel()
    }

    private struct RecentCell: View {
        @EnvironmentObject private var env: AppEnvironment
        let entry: LibraryEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if let design = entry.cardDesign {
                    ThumbnailView(assetID: entry.id, sourceURL: env.artworkURL(for: design))
                        .aspectRatio(CardGeometry.aspectRatio, contentMode: .fit)
                } else if let design = entry.wallpaperDesign {
                    ThumbnailView(assetID: entry.id, sourceURL: env.videoURL(for: design))
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                }
                Text(entry.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(entry.kind == .card ? "Card" : "Wallpaper")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
