// Draws the Instantools app icon into Resources/AppIcon.icns and Resources/AppIcon.png, and each tool's icon
// into Resources/InstantTab.png and Resources/InstantLang.png, which Settings and the menu show.
// Run with: swift scripts/make-icon.swift
import AppKit

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

struct Palette {
    let top: CGColor
    let bottom: CGColor

    init(top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat)) {
        self.top = CGColor(srgbRed: top.0, green: top.1, blue: top.2, alpha: 1)
        self.bottom = CGColor(srgbRed: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)
    }

    var gradient: CGGradient {
        CGGradient(colorsSpace: sRGB, colors: [top, bottom] as CFArray, locations: [0, 1])!
    }
}

/// Draws on the 1024 grid of macOS icons, whatever the pixel size.
struct Canvas {
    let context: CGContext
    let palette: Palette
    /// Pixels per grid point. Shadows ignore the transform, so they are scaled by hand.
    let scale: CGFloat

    func setShadow(y: CGFloat, blur: CGFloat, alpha: CGFloat) {
        context.setShadow(offset: CGSize(width: 0, height: y * scale), blur: blur * scale, color: CGColor(gray: 0, alpha: alpha))
    }

    func fill(_ path: CGPath, white alpha: CGFloat, shadow: Bool = false) {
        context.saveGState()
        if shadow { setShadow(y: -12, blur: 30, alpha: 0.25) }
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: alpha))
        context.fillPath()
        context.restoreGState()
    }

    /// The bolt all three icons share, 236 points tall at size 1.
    func bolt(center: CGPoint, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [(34, 118), (-62, -12), (-2, -12), (-30, -118), (66, 18), (6, 18)]
            .map { CGPoint(x: center.x + $0.0 * size, y: center.y + $0.1 * size) })
        path.closeSubpath()
        return path
    }

    /// A bolt in the icon's own gradient, running over the bolt's height.
    func gradientBolt(center: CGPoint, size: CGFloat) {
        context.saveGState()
        context.addPath(bolt(center: center, size: size))
        context.clip()
        context.drawLinearGradient(
            palette.gradient, start: CGPoint(x: center.x, y: center.y + 118 * size), end: CGPoint(x: center.x, y: center.y - 118 * size), options: []
        )
        context.restoreGState()
    }
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: CGFloat, palette: Palette, content: (Canvas) -> Void) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    // An 824pt rounded square with a 100pt margin.
    context.scaleBy(x: size / 1024, y: size / 1024)
    let canvas = Canvas(context: context, palette: palette, scale: size / 1024)

    // The shadow falls from the finished tile as a whole. A dark shape under it would show through its
    // antialiased edge as a gray line at small sizes.
    context.saveGState()
    canvas.setShadow(y: -10, blur: 24, alpha: 0.28)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 186))
    context.clip()
    context.drawLinearGradient(palette.gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: sRGB, colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 980), endRadius: 700, options: [])
    content(canvas)
    context.endTransparencyLayer()
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let instantools = (palette: Palette(top: (0.72, 0.45, 1.0), bottom: (0.36, 0.22, 0.90)), content: { (canvas: Canvas) in
    canvas.context.saveGState()
    canvas.setShadow(y: -14, blur: 34, alpha: 0.25)
    canvas.context.addPath(canvas.bolt(center: CGPoint(x: 512, y: 512), size: 2.6))
    canvas.context.setFillColor(.white)
    canvas.context.setStrokeColor(.white)
    // At 16 pixels the bolt's arms are about a pixel wide and blur away, so they get a little thicker.
    let thin = canvas.scale < 1.0 / 32
    canvas.context.setLineWidth(0.6 / canvas.scale)
    canvas.context.setLineJoin(.round)
    canvas.context.drawPath(using: thin ? .fillStroke : .fill)
    canvas.context.restoreGState()
})

/// Two windows, the bolt in the front one.
let instantTab = (palette: Palette(top: (0.38, 0.55, 1.0), bottom: (0.24, 0.25, 0.86)), content: { (canvas: Canvas) in
    canvas.fill(rounded(CGRect(x: 236, y: 404, width: 420, height: 320), 54), white: 0.38)
    canvas.fill(rounded(CGRect(x: 356, y: 290, width: 432, height: 330), 54), white: 1, shadow: true)
    canvas.gradientBolt(center: CGPoint(x: 572, y: 455), size: 1)
})

/// A rounded bubble whose tail carries its side down past a bottom corner, then curves back into its bottom.
func bubble(_ rect: CGRect, radius: CGFloat, tailRight: Bool) -> CGPath {
    // Drawn for the right corner, then mirrored.
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 0, y: radius))
    tail.addCurve(to: CGPoint(x: 14, y: -50), control1: CGPoint(x: 0, y: 30), control2: CGPoint(x: 2, y: -26))
    tail.addCurve(to: CGPoint(x: -radius, y: 0), control1: CGPoint(x: -18, y: -30), control2: CGPoint(x: -60, y: 0))
    tail.addLine(to: CGPoint(x: -radius, y: radius))
    tail.closeSubpath()
    var place = tailRight
        ? CGAffineTransform(translationX: rect.maxX, y: rect.minY)
        : CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: -1, y: 1)
    return rounded(rect, radius).union(tail.copy(using: &place)!)
}

/// Two speech bubbles, the bolt in the front one.
let instantLang = (palette: Palette(top: (0.22, 0.84, 0.80), bottom: (0.05, 0.47, 0.72)), content: { (canvas: Canvas) in
    canvas.fill(bubble(CGRect(x: 226, y: 474, width: 390, height: 262), radius: 104, tailRight: false), white: 0.38)
    let front = CGRect(x: 392, y: 296, width: 410, height: 294)
    canvas.fill(bubble(front, radius: 110, tailRight: true), white: 1, shadow: true)
    canvas.gradientBolt(center: CGPoint(x: front.midX + 4, y: front.midY), size: 0.9)
})

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources")
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try writePNG(drawIcon(size: CGFloat(points * scale), palette: instantools.palette, content: instantools.content), to: iconset.appending(path: name))
    }
}
try writePNG(drawIcon(size: 1024, palette: instantools.palette, content: instantools.content), to: resources.appending(path: "AppIcon.png"))
// 512 pixels covers the largest place a tool's icon is drawn, at 2x.
for (name, icon) in [("InstantTab", instantTab), ("InstantLang", instantLang)] {
    try writePNG(drawIcon(size: 512, palette: icon.palette, content: icon.content), to: resources.appending(path: "\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed")
    exit(iconutil.terminationStatus)
}
print("wrote Resources/AppIcon.icns, AppIcon.png, InstantTab.png and InstantLang.png")
