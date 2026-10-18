import CoreGraphics

/// Where dropping a dragged window snaps it, from the pointer alone, so it runs on every mouse move.
///
/// On a landscape monitor the left and right edges take halves, the top edge fills the screen, and the bottom
/// edge takes a third, picked by where along it the pointer is. A portrait monitor turns this a quarter: the
/// top and bottom edges take halves and the sides take thirds. The corners take quarters on both.
public enum SnapZones {
    /// How close to an edge the pointer must be. The pointer stops at the outer edges of the desktop, but
    /// passes through an edge shared with another monitor, so this is small enough not to catch a window
    /// dragged across and large enough to stop on.
    static let edge: CGFloat = 6
    /// How far along an edge from a corner the pointer takes a quarter rather than a half.
    static let corner: CGFloat = 40

    public static func action(at point: CGPoint, screens: [SnapScreen]) -> (action: SnapAction, screen: Int)? {
        guard let index = screens.firstIndex(where: { $0.frame.contains(point) }) else { return nil }
        let screen = screens[index]
        let frame = screen.frame
        let left = point.x - frame.minX < edge
        let right = frame.maxX - point.x <= edge
        let top = point.y - frame.minY < edge
        let bottom = frame.maxY - point.y <= edge
        guard left || right || top || bottom else { return nil }

        let nearTop = point.y - frame.minY < corner
        let nearBottom = frame.maxY - point.y <= corner
        let nearLeft = point.x - frame.minX < corner
        let nearRight = frame.maxX - point.x <= corner
        let action: SnapAction
        if (left && nearTop) || (top && nearLeft) {
            action = .topLeft
        } else if (right && nearTop) || (top && nearRight) {
            action = .topRight
        } else if (left && nearBottom) || (bottom && nearLeft) {
            action = .bottomLeft
        } else if (right && nearBottom) || (bottom && nearRight) {
            action = .bottomRight
        } else if screen.isPortrait {
            if top {
                action = .topHalf
            } else if bottom {
                action = .bottomHalf
            } else {
                action = third(at: point.y - frame.minY, of: frame.height)
            }
        } else if left {
            action = .leftHalf
        } else if right {
            action = .rightHalf
        } else if top {
            action = .maximize
        } else {
            action = third(at: point.x - frame.minX, of: frame.width)
        }
        return (action, index)
    }

    private static func third(at offset: CGFloat, of length: CGFloat) -> SnapAction {
        switch Int(offset / (length / 3)) {
        case ..<1: .firstThird
        case 1: .centerThird
        default: .lastThird
        }
    }
}
