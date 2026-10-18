import AppKit
import WindowSnapperCore

/// Converts between AppKit's screen coordinates, with the origin at the bottom left of the main display and y
/// up, and the AX ones every window frame is in, with the origin at its top left and y down.
@MainActor
enum Screens {
    /// Cheap enough to read fresh for every snap and every drag, so a moved Dock or a new monitor is never
    /// missed.
    static func current() -> [SnapScreen] {
        let height = mainHeight
        return NSScreen.screens.map { SnapScreen(frame: flip($0.frame, height), visible: flip($0.visibleFrame, height)) }
    }

    /// An AX frame as AppKit has it, for a window of this process.
    static func appKitFrame(_ frame: CGRect) -> CGRect {
        flip(frame, mainHeight)
    }

    /// In AX coordinates.
    nonisolated static func pointer() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// The first screen is the one with the menu bar, whose bottom left is AppKit's origin.
    private static var mainHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private static func flip(_ rect: CGRect, _ height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}
