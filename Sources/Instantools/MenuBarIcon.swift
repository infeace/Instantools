import AppKit

enum MenuBarIcon {
    /// The app icon's bolt, a little wider so it weighs about as much as the system's glyphs. Its middle bar
    /// sits on whole points, so it stays sharp at 1x.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let bolt: [(CGFloat, CGFloat)] = [(11.25, 16.5), (4.5, 8), (8.625, 8), (6.75, 1.5), (13.5, 10), (9.375, 10)]
            context.addLines(between: bolt.map { CGPoint(x: $0.0, y: $0.1) })
            context.closePath()
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Instantools"
        return image
    }
}
