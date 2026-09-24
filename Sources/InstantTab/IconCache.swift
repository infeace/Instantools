import AppKit
import UniformTypeIdentifiers

/// App icons pre-rendered to bitmaps when apps appear, so showing the switcher only assigns layer contents.
@MainActor
final class IconCache {
    /// Large enough for a 128pt icon on a 2x display. Layers scale it down with trilinear filtering.
    private static let pixels = 256
    private var icons: [Int32: CGImage] = [:]
    private lazy var placeholder = Self.render(NSWorkspace.shared.icon(for: .applicationBundle))

    func icon(for pid: Int32) -> CGImage? {
        if let icon = icons[pid] { return icon }
        guard let app = NSRunningApplication(processIdentifier: pid), let image = app.icon else { return placeholder }
        let icon = Self.render(image)
        icons[pid] = icon
        return icon
    }

    /// Renders icons for new pids and forgets pids that are gone.
    func sync(with pids: [Int32]) {
        let live = Set(pids)
        icons = icons.filter { live.contains($0.key) }
        for pid in pids where icons[pid] == nil {
            _ = icon(for: pid)
        }
        _ = placeholder
    }

    private static func render(_ image: NSImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
