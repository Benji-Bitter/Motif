import SwiftUI
import MotifCore

/// Interactive iPhone lock-screen preview: wallpaper art, live clock, date,
/// realistic safe-area proportions and an optional dim overlay.
struct LockScreenPreview: View {
    let image: CGImage?
    var preset: DisplayPreset = .iPhone14Plus
    var dimmed: Bool = false
    var height: CGFloat = 340

    private var width: CGFloat { height * CGFloat(preset.aspectRatio) }

    var body: some View {
        ZStack {
            // Wallpaper
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.black)
                        .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.3)))
                }
            }

            if dimmed { Rectangle().fill(.black.opacity(0.35)) }

            // Lock screen chrome
            VStack(spacing: 4) {
                // Safe-area gap: clock sits ~18% down on tall iPhones.
                Spacer().frame(height: height * 0.14)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 0) {
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.system(size: height * 0.045, weight: .medium))
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: height * 0.14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 4, y: 1)
                }

                Spacer()

                // Bottom hint + controls.
                Text("Swipe up to open")
                    .font(.system(size: height * 0.032, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, height * 0.028)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.09, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: height * 0.09, style: .continuous)
                .strokeBorder(Motif.Colors.panelStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .overlay(alignment: .top) {
            // Dynamic-Island-ish notch hint (dark pill).
            Capsule()
                .fill(.black)
                .frame(width: width * 0.28, height: height * 0.03)
                .padding(.top, height * 0.015)
        }
        .accessibilityLabel("Lock screen preview")
    }
}
