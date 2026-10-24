import SwiftUI
import AVFoundation
import MotifCore

/// Trim timeline: thumbnail strip with draggable start/end handles and a
/// diamond marker for the Live Photo still frame.
struct TrimTimelineView: View {
    @Binding var start: Double
    @Binding var end: Double
    @Binding var still: Double
    let duration: Double
    let thumbnails: [CGImage]
    var onStroke: () -> Void = {}

    @State private var dragStart: Double?
    @State private var dragEnd: Double?
    @State private var dragStill: Double?

    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    thumbnailStrip(width: w)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Dimmed areas outside the trim range.
                    dimRect(x: 0, width: x(for: start, in: w))
                    dimRect(x: x(for: end, in: w), width: w - x(for: end, in: w))

                    // Still marker (diamond).
                    stillMarker(in: w)
                        .position(x: x(for: still, in: w), y: trackHeight + 11)

                    // Handles.
                    handle
                        .gesture(handleDrag(in: w, isStart: true))
                        .position(x: x(for: start, in: w), y: trackHeight / 2)
                    handle
                        .gesture(handleDrag(in: w, isStart: false))
                        .position(x: x(for: end, in: w), y: trackHeight / 2)
                }
                .frame(height: trackHeight + 22)
            }
            .frame(height: trackHeight + 22)

            HStack {
                Label(String(format: "%.2fs", start), systemImage: "scissors")
                Spacer()
                Text("Still @ \(String(format: "%.2f", still))s")
                Spacer()
                Text(String(format: "%.2fs end · %.2fs long", end, end - start))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func thumbnailStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            if thumbnails.isEmpty {
                Rectangle().fill(Motif.Colors.panelFill)
            }
        }
        .frame(width: width, height: trackHeight)
        .clipped()
    }

    private func dimRect(x: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(.black.opacity(0.55))
            .frame(width: max(0, width), height: trackHeight)
            .position(x: x + max(0, width) / 2, y: trackHeight / 2)
    }

    private func stillMarker(in width: CGFloat) -> some View {
        Image(systemName: "diamond.fill")
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .shadow(radius: 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStill == nil { dragStill = still }
                        let next = (dragStill ?? 0) + value.translation.width / width * duration
                        still = min(max(next, start), end)
                    }
                    .onEnded { _ in dragStill = nil; onStroke() }
            )
            .help("Still frame time — the Live Photo's photo")
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.white)
            .frame(width: handleWidth, height: trackHeight)
            .shadow(radius: 1)
    }

    private func handleDrag(in width: CGFloat, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isStart {
                    if dragStart == nil { dragStart = start }
                    let next = (dragStart ?? 0) + value.translation.width / width * duration
                    start = max(0, min(next, end - 0.1))
                    if still < start { still = start }
                } else {
                    if dragEnd == nil { dragEnd = end }
                    let next = (dragEnd ?? 0) + value.translation.width / width * duration
                    end = min(duration, max(next, start + 0.1))
                    if still > end { still = end }
                }
            }
            .onEnded { _ in
                dragStart = nil
                dragEnd = nil
                onStroke()
            }
    }

    private func x(for time: Double, in width: CGFloat) -> CGFloat {
        CGFloat(time / max(duration, 0.001)) * width
    }
}
