import AppKit
import InstantoolsCore

/// Each tool's icon, Resources/<name>.png, drawn by scripts/make-icon.swift. Nil when running unbundled, as
/// with `swift run`, where callers fall back to a symbol or to no image.
@MainActor
enum ToolIcons {
    private static let images: [ToolId: NSImage] = Dictionary(uniqueKeysWithValues: ToolId.allCases.compactMap { tool in
        Bundle.main.image(forResource: tool.name).map { (tool, $0) }
    })

    /// Drawn smoothly at 16 points from the one large image, which the menu would otherwise scale down itself.
    private static let menuImages: [ToolId: NSImage] = images.mapValues { icon in
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            icon.draw(in: rect)
            return true
        }
    }

    static func image(for tool: ToolId) -> NSImage? {
        images[tool]
    }

    static func menuImage(for tool: ToolId) -> NSImage? {
        menuImages[tool]
    }
}
