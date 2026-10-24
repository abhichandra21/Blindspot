// Draws the Blindspot app icon and writes assets/Blindspot.icns.
// Run from the repository root: swift assets/make-icon.swift
// Uses only AppKit and the built-in iconutil, so it needs no image tools.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets/Blindspot.icns")

// A blue tile, a white shield, and a red dot: the spot that may be exposed.
// Coordinates are fractions of the canvas, with the origin at the bottom left.
func drawIcon(size pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    // At 16 px the usual margin leaves too few pixels for the shield shape,
    // so the tile fills more of the canvas and the shield is drawn larger.
    let tiny = pixels <= 16
    let margin: CGFloat = tiny ? 0.03 : 0.1
    let shieldScale: CGFloat = tiny ? 1.25 : 1
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: (0.5 + (x - 0.5) * shieldScale) * s, y: (0.5 + (y - 0.5) * shieldScale) * s)
    }

    // Same tile margins as other macOS app icons, except at 16 px.
    let tile = NSRect(x: margin * s, y: margin * s, width: (1 - 2 * margin) * s, height: (1 - 2 * margin) * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 0.18 * s, yRadius: 0.18 * s)
    NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.48, blue: 0.93, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.23, blue: 0.62, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    let shield = NSBezierPath()
    shield.move(to: p(0.5, 0.78))
    shield.curve(to: p(0.74, 0.70), controlPoint1: p(0.58, 0.74), controlPoint2: p(0.66, 0.71))
    shield.line(to: p(0.74, 0.52))
    shield.curve(to: p(0.5, 0.20), controlPoint1: p(0.74, 0.36), controlPoint2: p(0.62, 0.26))
    shield.curve(to: p(0.26, 0.52), controlPoint1: p(0.38, 0.26), controlPoint2: p(0.26, 0.36))
    shield.line(to: p(0.26, 0.70))
    shield.curve(to: p(0.5, 0.78), controlPoint1: p(0.34, 0.71), controlPoint2: p(0.42, 0.74))
    shield.close()
    NSColor.white.setFill()
    shield.fill()

    // A larger dot at the smallest sizes, so it stays visible.
    let radius = (tiny ? 0.11 * shieldScale : pixels <= 32 ? 0.12 : 0.10) * s
    let center = p(0.5, 0.50)
    NSColor(srgbRed: 0.90, green: 0.18, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Blindspot-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try drawIcon(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try drawIcon(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed with status \(iconutil.terminationStatus)")
    exit(1)
}
print("wrote \(output.path)")
