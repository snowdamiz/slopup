#!/usr/bin/env swift

// Renders Resources/AppIcon.icns from the menu bar glyph (MenuBarIcon.svg):
// a macOS squircle with a warm gradient and the white sloppy-joe silhouette.
//
//   swift Scripts/make-icon.swift

import AppKit
import SwiftUI

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let projectDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let glyphURL = projectDir.appendingPathComponent("Sources/Slopup/Resources/MenuBarIcon.svg")
let outputURL = projectDir.appendingPathComponent("Resources/AppIcon.icns")

guard let glyph = NSImage(contentsOf: glyphURL) else {
    fputs("error: could not load \(glyphURL.path)\n", stderr)
    exit(1)
}
glyph.isTemplate = true

/// ImageRenderer rasterizes an SVG-backed NSImage at its intrinsic 18pt size, so
/// draw it into a bitmap at the exact pixel size first to keep the edges crisp.
func rasterized(_ image: NSImage, pixels: Int) -> NSImage {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return image }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let output = NSImage(size: rep.size)
    output.addRepresentation(rep)
    output.isTemplate = true
    return output
}

struct AppIconView: View {
    let size: CGFloat
    let glyph: NSImage

    var body: some View {
        // Apple's macOS icon grid: the shape spans ~824 of a 1024 canvas.
        let shape = RoundedRectangle(cornerRadius: size * 0.1806, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.58, blue: 0.32),
                        Color(red: 0.87, green: 0.27, blue: 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.22), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            shape.strokeBorder(.white.opacity(0.14), lineWidth: max(1, size * 0.004))

            Image(nsImage: glyph)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: size * 0.64, height: size * 0.64)
                .shadow(color: .black.opacity(0.28), radius: size * 0.018, y: size * 0.012)
        }
        .padding(size * 0.0977)
        .frame(width: size, height: size)
    }
}

@MainActor
func renderPNG(pixels: CGFloat) -> Data? {
    let glyphBitmap = rasterized(glyph, pixels: Int((pixels * 0.64).rounded()))
    let renderer = ImageRenderer(content: AppIconView(size: pixels, glyph: glyphBitmap))
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

for entry in entries {
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    guard let png = MainActor.assumeIsolated({ renderPNG(pixels: CGFloat(entry.points * entry.scale)) }) else {
        fputs("error: failed to render \(name)\n", stderr)
        exit(1)
    }
    try png.write(to: iconsetURL.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("error: iconutil failed\n", stderr)
    exit(1)
}

// Keep a 1024px preview next to the iconset for inspection when requested.
if CommandLine.arguments.contains("--preview") {
    let previewURL = URL(fileURLWithPath: "/tmp/slopup_appicon_preview.png")
    try? FileManager.default.copyItem(at: iconsetURL.appendingPathComponent("icon_512x512@2x.png"), to: previewURL)
    print("preview: \(previewURL.path)")
}
try? FileManager.default.removeItem(at: iconsetURL)
print("wrote \(outputURL.path)")
