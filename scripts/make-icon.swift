// Draws the InstantTab app icon and writes Resources/AppIcon.icns.
// Run with: swift scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    // Design on the 1024 grid of macOS icons: an 824pt rounded square with a 100pt margin.
    context.scaleBy(x: size / 1024, y: size / 1024)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(white: 0, alpha: 0.28).cgColor)
    context.addPath(tilePath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let top = NSColor(srgbRed: 0.38, green: 0.55, blue: 1.0, alpha: 1)
    let bottom = NSColor(srgbRed: 0.24, green: 0.25, blue: 0.86, alpha: 1)
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft light from the top.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [NSColor(white: 1, alpha: 0.22).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 980), endRadius: 700, options: [])

    // Two windows: the one behind, and the one being switched to.
    func window(_ rect: CGRect, alpha: CGFloat) {
        let path = CGPath(roundedRect: rect, cornerWidth: 54, cornerHeight: 54, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor(white: 1, alpha: alpha).cgColor)
        context.fillPath()
    }
    window(CGRect(x: 236, y: 404, width: 420, height: 320), alpha: 0.38)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor(white: 0, alpha: 0.25).cgColor)
    window(CGRect(x: 356, y: 290, width: 432, height: 330), alpha: 1)
    context.restoreGState()

    // A lightning bolt on the front window.
    let center = CGPoint(x: 572, y: 455)
    let bolt: [CGPoint] = [(34, 118), (-62, -12), (-2, -12), (-30, -118), (66, 18), (6, 18)]
        .map { CGPoint(x: center.x + $0.0, y: center.y + $0.1) }
    context.beginPath()
    context.addLines(between: bolt)
    context.closePath()
    context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: center.x, y: center.y + 118), end: CGPoint(x: center.x, y: center.y - 118), options: [])
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appending(path: name))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: root.appending(path: "Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed")
    exit(iconutil.terminationStatus)
}
print("wrote Resources/AppIcon.icns")
