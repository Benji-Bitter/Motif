import Foundation
import CoreGraphics

/// A small set of original, procedurally generated card artworks installed on
/// first launch so the library isn't empty. No copyrighted artwork ships in
/// the repository — these are drawn by Motif itself.
public enum ExampleAssets {

    public static func installIfNeeded(into store: LibraryStore) async throws {
        let marker = store.paths.root.appendingPathComponent(".examples-installed")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        defer { FileManager.default.createFile(atPath: marker.path, contents: Data()) }

        let processor = ImageProcessor()
        for spec in examples {
            guard let image = render(spec) else { continue }
            let data = try processor.pngData(of: image)
            let fileName = try await store.storeMediaData(data, fileName: "\(UUID().uuidString).png")
            var design = CardDesign(title: spec.name, artworkFileName: fileName)
            design.edit = spec.edit
            try await store.saveCardDesign(design)
            try await store.addTag(id: design.id, tag: "example")
        }
    }

    private struct Spec {
        var name: String
        var edit: CardEditParameters
        var draw: (CGContext, CGSize) -> Void
    }

    private static let canvas = CGSize(width: 1536, height: 969)

    private static var examples: [Spec] {
        [
            Spec(name: "Example — Arcs", edit: .default) { ctx, size in
                ctx.setFillColor(CGColor(gray: 0.07, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: size))
                for i in 0..<9 {
                    let inset = Double(i) * 90
                    let rect = CGRect(x: -inset, y: -inset,
                                      width: size.width + inset * 2,
                                      height: size.height * 2 + inset)
                    ctx.setStrokeColor(CGColor(gray: 0.15 + Double(i) * 0.09, alpha: 1))
                    ctx.setLineWidth(34)
                    ctx.strokeEllipse(in: rect)
                }
            },
            Spec(name: "Example — Weave", edit: .default) { ctx, size in
                ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.setLineWidth(48)
                for i in stride(from: -size.height, to: size.width, by: 136.0) {
                    let shade = 0.2 + 0.55 * abs(sin(Double(i) / 300))
                    ctx.setStrokeColor(CGColor(gray: shade, alpha: 1))
                    ctx.move(to: CGPoint(x: i, y: 0))
                    ctx.addLine(to: CGPoint(x: i + size.height, y: size.height))
                    ctx.strokePath()
                }
            },
            Spec(name: "Example — Horizon", edit: .default) { ctx, size in
                let bands: [(CGFloat, CGFloat)] = [
                    (0.0, 0.95), (0.5, 0.8), (1.0, 0.6)
                ]
                for (start, gray) in bands {
                    let rect = CGRect(x: 0, y: size.height * start * 0.45,
                                      width: size.width, height: size.height)
                    ctx.setFillColor(CGColor(gray: gray, alpha: 1))
                    ctx.fill(rect)
                }
                ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: size.width * 0.62, y: size.height * 0.5,
                                           width: 260, height: 260))
            }
        ]
    }

    private static func render(_ spec: Spec) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: Int(canvas.width), height: Int(canvas.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        spec.draw(ctx, canvas)
        return ctx.makeImage()
    }
}
