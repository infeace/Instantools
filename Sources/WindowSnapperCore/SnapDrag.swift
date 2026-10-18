import CoreGraphics

/// Telling a window being moved by its title bar from any other drag, by its frame when the button went
/// down and now.
public enum SnapDrag {
    public enum Kind: Equatable, Sendable {
        case moving
        /// Nothing has moved yet, as when the app is slow to follow, or the drag selects text.
        case notYet
        /// A resize, or something else that changed the window's size.
        case other
    }

    /// A move keeps the size exactly. Dragging the left or top edge moves the origin too, but changes the
    /// size by as much.
    public static func classify(start: CGRect, now: CGRect) -> Kind {
        guard abs(now.width - start.width) < 0.5, abs(now.height - start.height) < 0.5 else { return .other }
        return abs(now.minX - start.minX) >= 1 || abs(now.minY - start.minY) >= 1 ? .moving : .notYet
    }

    /// A snapped window dragged away goes back to its size from before, staying under the pointer at the same
    /// share of its width as where it was grabbed, with its top where it is.
    public static func unsnapped(_ window: CGRect, grabbedAt grab: CGPoint, start: CGRect, previousSize: CGSize, pointer: CGPoint) -> CGRect {
        let share = min(max((grab.x - start.minX) / max(start.width, 1), 0), 1)
        return CGRect(x: (pointer.x - share * previousSize.width).rounded(), y: window.minY, width: previousSize.width, height: previousSize.height)
    }
}
