import SwiftUI
import MotifCore

/// Async-loading thumbnail image. Falls back to a neutral placeholder and
/// never blocks the main thread.
struct ThumbnailView: View {
    let assetID: UUID
    let sourceURL: URL
    var maxPixel: Int = 256
    var cornerRadius: CGFloat = Motif.Metrics.smallCorner

    @EnvironmentObject private var env: AppEnvironment
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Motif.Colors.panelFill)
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: assetID) {
            image = await env.thumbnails.thumbnail(
                assetID: assetID, sourceURL: sourceURL, maxPixel: maxPixel)
        }
    }
}
