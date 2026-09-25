import AppKit

/// How the switcher draws names and key badges. The Cmd+Tab tool's panel and the Settings preview both use
/// it, so the preview matches what Cmd+Tab shows.
@MainActor
public enum PanelStyle {
    public static let nameFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    /// Apps with no visible window, like hidden apps in the Dock.
    public static let dimmedOpacity: Float = 0.5

    private static var badgeImages: [Character: CGImage] = [:]

    /// The state follows the name in a lighter color.
    public static func nameText(name: String, state: String?, dark: Bool) -> NSAttributedString {
        let text = NSMutableAttributedString(string: name, attributes: [.font: nameFont, .foregroundColor: dark ? NSColor.white : NSColor.black])
        if let state {
            let color = NSColor(white: dark ? 1 : 0, alpha: 0.5)
            text.append(NSAttributedString(string: " · \(state)", attributes: [.font: nameFont, .foregroundColor: color]))
        }
        return text
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

    /// Dark in both appearances, so it reads on any icon.
    private static func renderBadge(_ key: Character) -> CGImage? {
        let pixels: CGFloat = 64
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: Int(pixels), height: Int(pixels), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
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
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Matches what the name layer draws, so a label this wide is never truncated.
    public static func width(of text: NSAttributedString) -> CGFloat {
        text.size().width.rounded(.up)
    }
}
