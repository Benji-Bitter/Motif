#!/usr/bin/env swift
// Generates Resources/AppIcon.icns — a minimal monochrome "M" mark on a
// rounded dark tile. Run:  swift Scripts/generate_icon.swift
import AppKit
import CoreGraphics

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)

    // Rounded dark tile (icon-corner radius ≈ 22.37% per macOS guidance).
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2237, yRadius: s * 0.2237)
    NSColor(white: 0.07, alpha: 1).setFill()
    path.fill()

    // "M" glyph in white, centered, ~62% of the tile.
    let font = NSFont.systemFont(ofSize: s * 0.52, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor(white: 0.95, alpha: 1)]
    let str = NSAttributedString(string: "M", attributes: attrs)
    let strSize = str.size()
    str.draw(at: CGPoint(x: (s - strSize.width) / 2, y: (s - strSize.height) / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for entry in sizes {
    guard let rep = drawIcon(size: entry.px),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not render \(entry.name)")
    }
    try png.write(to: iconset.appendingPathComponent(entry.name))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "✓ \(icns.path)" : "iconutil failed")
