// Draws the Blindspot app icon and writes assets/Blindspot.icns.
// Run from the repository root: swift assets/make-icon.swift
// Uses only AppKit and the built-in iconutil, so it needs no image tools.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets/Blindspot.icns")

// A blue tile with a white display and an eye on it; the red pupil is the spot that may be exposed.
// Coordinates are fractions of the canvas, with the origin at the bottom left.
func drawIcon(size pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    // At 16 px the usual margin leaves too few pixels for the drawing,
    // so the tile fills more of the canvas and the drawing is larger.
    let tiny = pixels <= 16
    let margin: CGFloat = tiny ? 0.03 : 0.1
    let drawScale: CGFloat = tiny ? 1.25 : 1
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: (0.5 + (x - 0.5) * drawScale) * s, y: (0.5 + (y - 0.5) * drawScale) * s)
    }

    // Same tile margins as other macOS app icons, except at 16 px.
    let tile = NSRect(x: margin * s, y: margin * s, width: (1 - 2 * margin) * s, height: (1 - 2 * margin) * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 0.18 * s, yRadius: 0.18 * s)
    NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.48, blue: 0.93, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.23, blue: 0.62, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    // A white display with an eye on it, like the menu bar icon. The red pupil
    // is the spot that may be exposed.
    let line = (tiny ? 0.075 : 0.045) * s
    NSColor.white.set()
    let screen = NSBezierPath(roundedRect: NSRect(x: p(0.22, 0.36).x, y: p(0.22, 0.36).y,
                                                  width: p(0.78, 0).x - p(0.22, 0).x,
                                                  height: p(0, 0.74).y - p(0, 0.36).y),
                              xRadius: 0.05 * s, yRadius: 0.05 * s)
    screen.lineWidth = line
    screen.stroke()
    let stand = NSBezierPath()
    stand.move(to: p(0.40, 0.25))
    stand.line(to: p(0.60, 0.25))
    stand.lineWidth = line
    stand.lineCapStyle = .round
    stand.stroke()

    // Cubic control points at 4/3 of the height give a peak of exactly the height.
    let c = p(0.5, 0.55), w = p(0.67, 0).x - c.x, h = p(0, 0.65).y - c.y
    let eye = NSBezierPath()
    eye.move(to: NSPoint(x: c.x - w, y: c.y))
    eye.curve(to: NSPoint(x: c.x + w, y: c.y), controlPoint1: NSPoint(x: c.x - w / 2, y: c.y + h * 4 / 3),
              controlPoint2: NSPoint(x: c.x + w / 2, y: c.y + h * 4 / 3))
    eye.curve(to: NSPoint(x: c.x - w, y: c.y), controlPoint1: NSPoint(x: c.x + w / 2, y: c.y - h * 4 / 3),
              controlPoint2: NSPoint(x: c.x - w / 2, y: c.y - h * 4 / 3))
    eye.fill()

    // A larger pupil at the smallest sizes, so it stays visible.
    let radius = (tiny ? 0.075 : pixels <= 32 ? 0.065 : 0.055) * s * drawScale
    NSColor(srgbRed: 0.90, green: 0.18, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()

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
