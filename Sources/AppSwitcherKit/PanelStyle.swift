import AppKit

/// How the switcher looks: its metrics, colors, names and key badges. The Cmd+Tab tool's panel and the
/// Settings preview both use it, so the preview matches what Cmd+Tab shows.
@MainActor
public enum PanelStyle {
    public static let padding: CGFloat = 14
    /// The strip under the tiles for the selected app's name, which sits at its bottom below a gap.
    public static let nameHeight: CGFloat = 26
    public static let nameGap: CGFloat = 6
    public static let nameLabelHeight = nameHeight - nameGap
    public static let cornerRadius: CGFloat = 22
    public static let highlightCornerRadius: CGFloat = 14
    public static let nameFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    public static let maxTileInset: CGFloat = 10

    public static func tileSize(iconSize: CGFloat) -> CGFloat {
        iconSize + 2 * maxTileInset
    }

    /// Tiles shrunk to fit many apps keep a smaller margin around the icon.
    public static func tileInset(tile: CGFloat) -> CGFloat {
        min(maxTileInset, (tile * 0.1).rounded(.down))
    }

    public static func nameMaxWidth(tile: CGFloat) -> CGFloat {
        max(tile * 2.5, 160)
    }

    /// A gray and its opacity rather than a color, so the panel builds an NSColor and the preview a
    /// SwiftUI Color without SwiftUI in the Cmd+Tab tool.
    public struct Shade: Sendable {
        public let white: CGFloat
        public let alpha: CGFloat

        public var cgColor: CGColor { NSColor(white: white, alpha: alpha).cgColor }
    }

    public static func background(dark: Bool) -> Shade {
        dark ? Shade(white: 0.14, alpha: 0.9) : Shade(white: 0.96, alpha: 0.9)
    }

    public static func border(dark: Bool) -> Shade {
        dark ? Shade(white: 1, alpha: 0.12) : Shade(white: 0, alpha: 0.1)
    }

    public static func highlight(dark: Bool) -> Shade {
        dark ? Shade(white: 1, alpha: 0.16) : Shade(white: 0, alpha: 0.1)
    }

    private static var badgeImages: [Character: CGImage] = [:]

    public static func nameText(name: String, dark: Bool) -> NSAttributedString {
        NSAttributedString(string: name, attributes: [.font: nameFont, .foregroundColor: dark ? NSColor.white : NSColor.black])
    }

    public static func badgeSize(icon: CGFloat) -> CGFloat {
        min(max((icon * 0.26).rounded(), 14), 30)
    }

    public static func badgeImage(_ key: Character) -> CGImage? {
        if let image = badgeImages[key] { return image }
        let image = renderBadge(key)
        badgeImages[key] = image
        return image
    }

    public static func renderImage(pixels: Int, _ draw: () -> Void) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Dark in both appearances, so it reads on any icon.
    private static func renderBadge(_ key: Character) -> CGImage? {
        let pixels: CGFloat = 64
        return renderImage(pixels: Int(pixels)) {
            let shape = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: pixels - 4, height: pixels - 4), xRadius: 15, yRadius: 15)
            NSColor(white: 0.1, alpha: 0.8).setFill()
            shape.fill()
            NSColor(white: 1, alpha: 0.35).setStroke()
            shape.lineWidth = 2
            shape.stroke()
            let font = NSFont.systemFont(ofSize: 36, weight: .semibold)
            let text = NSAttributedString(string: String(key).uppercased(), attributes: [.font: font, .foregroundColor: NSColor.white])
            // Centers the capital or digit itself rather than the line, which includes the descender.
            text.draw(at: NSPoint(x: (pixels - text.size().width) / 2, y: (pixels - font.capHeight) / 2 + font.descender))
        }
    }

    /// Matches what the name layer draws, so a label this wide is never truncated.
    public static func width(of text: NSAttributedString) -> CGFloat {
        text.size().width.rounded(.up)
    }
}
