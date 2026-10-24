import SwiftUI
import MotifCore

/// Motif's restrained monochrome design language: black/white/greys, system
/// typography, rounded panels, subtle strokes, no gradients or neon.
enum Motif {
    enum Colors {
        static let panelFill = Color.primary.opacity(0.045)
        static let panelStroke = Color.primary.opacity(0.10)
        static let hairline = Color.primary.opacity(0.14)
        static let subtleText = Color.secondary
        static let cardBack = Color.black
        static let ok = Color.green
        static let warn = Color.orange
        static let bad = Color.red
        static let manual = Color.blue
    }

    enum Metrics {
        static let corner: CGFloat = 14
        static let smallCorner: CGFloat = 9
        static let panelPadding: CGFloat = 16
        static let gap: CGFloat = 12
    }
}

/// Rounded neutral panel used everywhere for content grouping.
struct Panel: ViewModifier {
    var padding: CGFloat = Motif.Metrics.panelPadding
    var corner: CGFloat = Motif.Metrics.corner

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Motif.Colors.panelFill, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Motif.Colors.panelStroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel(padding: CGFloat = Motif.Metrics.panelPadding,
               corner: CGFloat = Motif.Metrics.corner) -> some View {
        modifier(Panel(padding: padding, corner: corner))
    }
}

/// Small status pill that honestly reflects availability/operation states.
struct StatusBadge: View {
    var text: String
    var color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    init(status: OperationStatus) {
        switch status {
        case .pending: self.init(status.label, color: .secondary)
        case .checking, .preparing, .applying: self.init(status.label, color: Motif.Colors.warn)
        case .supported: self.init(status.label, color: Motif.Colors.ok)
        case .succeeded: self.init(status.label, color: Motif.Colors.ok)
        case .requiresManual: self.init(status.label, color: Motif.Colors.manual)
        case .notTested: self.init(status.label, color: Motif.Colors.warn)
        case .unsupported, .failed: self.init(status.label, color: Motif.Colors.bad)
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Section header used across panels.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Consistent device row icon.
struct DeviceIcon: View {
    var body: some View {
        Image(systemName: "iphone")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.primary)
    }
}
