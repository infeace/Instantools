import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let back = CGPath(roundedRect: CGRect(x: 1, y: 7.5, width: 10.5, height: 8), cornerWidth: 2, cornerHeight: 2, transform: nil)
            let frontRect = CGRect(x: 4.5, y: 2.5, width: 12.5, height: 9.5)
            let front = CGPath(roundedRect: frontRect, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)

            context.addPath(back)
            context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            context.fillPath()

            context.setBlendMode(.clear)
            context.addPath(CGPath(roundedRect: frontRect.insetBy(dx: -1.2, dy: -1.2), cornerWidth: 3.2, cornerHeight: 3.2, transform: nil))
            context.fillPath()
            context.setBlendMode(.normal)

            let center = CGPoint(x: frontRect.midX + 0.2, y: frontRect.midY)
            let bolt = CGMutablePath()
            bolt.addLines(between: [(1.1, 3.7), (-2.0, -0.4), (-0.1, -0.4), (-1.0, -3.7), (2.1, 0.6), (0.2, 0.6)]
                .map { CGPoint(x: center.x + $0.0, y: center.y + $0.1) })
            bolt.closeSubpath()
            context.addPath(front)
            context.addPath(bolt)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "InstantTab"
        return image
    }
}
