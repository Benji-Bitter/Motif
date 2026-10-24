import SwiftUI
import MotifCore

/// The central apply workflow: plan → confirm → execute → honest results.
/// Nothing reports success until the operation actually finished and was
/// checked.
struct ApplySheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var plan: [ApplyOperation] = []
    @State private var blockers: [String] = []
    @State private var running = false
    @State private var finished = false
    @State private var progress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    deviceSummary
                    if !blockers.isEmpty { blockersPanel }
                    operationsPanel
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 620)
        .task { await evaluate() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apply to iPhone").font(.title2.weight(.semibold))
                Text("Every operation is checked against the connected device first — nothing is faked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(20)
    }

    private var deviceSummary: some View {
        HStack(spacing: 12) {
            DeviceIcon()
            VStack(alignment: .leading, spacing: 2) {
                if let device = env.deviceManager.selectedDevice {
                    Text(device.name).font(.headline)
                    Text("\(device.modelName) · iOS \(device.iosVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No iPhone connected").font(.headline)
                    Text("Connect and unlock an iPhone, then trust this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let device = env.deviceManager.selectedDevice {
                StatusBadge(
                    device.connectionState == .ready ? "Trusted" : "Not ready",
                    color: device.connectionState == .ready ? Motif.Colors.ok : Motif.Colors.warn)
            }
        }
        .panel()
    }

    private var blockersPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Blocked")
            ForEach(blockers, id: \.self) { blocker in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Motif.Colors.warn)
                    Text(blocker).font(.callout)
                }
            }
        }
        .panel()
    }

    private var operationsPanel: some View {
        VStack(alignment: .leading, spacing: Motif.Metrics.gap) {
            SectionHeader(title: "Operations")
            if plan.isEmpty {
                Text("Select a card design in Wallet Studio or a wallpaper in Wallpaper Studio first.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(plan) { op in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            statusIcon(op.status)
                            Text(op.title).font(.callout.weight(.medium))
                            Spacer()
                            StatusBadge(status: op.status)
                        }
                        if let detail = op.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Divider().opacity(0.4)
                }
            }
        }
        .panel()
    }

    private func statusIcon(_ status: OperationStatus) -> some View {
        Group {
            switch status {
            case .succeeded:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Motif.Colors.ok)
            case .failed, .unsupported:
                Image(systemName: "xmark.circle.fill").foregroundStyle(Motif.Colors.bad)
            case .requiresManual, .notTested:
                Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(Motif.Colors.manual)
            case .preparing, .applying, .checking:
                ProgressView().controlSize(.small)
            case .pending, .supported:
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if running {
                ProgressView(value: progress).frame(maxWidth: 180)
                Text("Working…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !finished {
                Button("Cancel") { dismiss() }
                Button("Apply") { Task { await run() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(running || !blockers.isEmpty || plan.isEmpty)
            } else {
                Button("Reveal Exports") {
                    NSWorkspace.shared.activateFileViewerSelecting([env.store.paths.exports])
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private func evaluate() async {
        let context = env.applyContext(card: env.activeCard, wallpaper: env.activeWallpaper)
        plan = await env.applyEngine.plan(for: context)
        blockers = await env.applyEngine.blockers(for: context, plan: plan)
    }

    private func run() async {
        running = true
        let context = env.applyContext(card: env.activeCard, wallpaper: env.activeWallpaper)
        let stream = await env.applyEngine.execute(context: context, plan: plan) { p in
            Task { @MainActor in progress = p }
        }
        do {
            for try await op in stream {
                if let idx = plan.firstIndex(where: { $0.id == op.id }) {
                    plan[idx] = op
                }
            }
        } catch {
            env.alert = .init(title: "Apply failed", message: error.localizedDescription)
        }
        running = false
        finished = true
    }
}
