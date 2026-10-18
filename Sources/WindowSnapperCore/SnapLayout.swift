import CoreGraphics

/// A display in the global coordinates AX and CGWindowList share, with the origin at the top left of the
/// main display and y growing down.
public struct SnapScreen: Equatable, Sendable {
    public var frame: CGRect
    /// Without the menu bar and the Dock.
    public var visible: CGRect

    public init(frame: CGRect, visible: CGRect) {
        self.frame = frame
        self.visible = visible
    }

    /// Thirds run top to bottom on a portrait monitor, and the drag zones turn with it.
    var isPortrait: Bool { frame.height > frame.width }
}

/// What the last snap did to a window, so pressing the same shortcut again can go further.
public struct SnapRecord: Equatable, Sendable {
    public var action: SnapAction
    /// The size step of a half under `cycleSizes`: a half, two thirds, then one third.
    public var step: Int
    /// The frame the window ended up with, which an app with a size grid such as Terminal can round.
    public var frame: CGRect

    public init(action: SnapAction, step: Int = 0, frame: CGRect) {
        self.action = action
        self.step = step
        self.frame = frame
    }
}

public struct SnapPlan: Equatable, Sendable {
    public var frame: CGRect
    public var action: SnapAction
    public var step: Int

    init(frame: CGRect, action: SnapAction, step: Int = 0) {
        self.frame = frame
        self.action = action
        self.step = step
    }
}

public enum SnapLayout {
    /// How far a window may be from where a snap put it and still count as left there.
    static let tolerance: CGFloat = 2
    private static let halfSteps: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]

    /// Where `action` puts a window now at `window`. Nil when it has nowhere to go, such as a half pressed
    /// again with no monitor further that way, and for `restore`, which only the caller can do.
    public static func plan(
        _ action: SnapAction, window: CGRect, screens: [SnapScreen], last: SnapRecord?,
        repeatMode: RepeatMode, gap: CGFloat
    ) -> SnapPlan? {
        guard let index = screenIndex(for: window, in: screens) else { return nil }
        let screen = screens[index]
        let repeated = last.map { $0.action == action && $0.frame.isClose(to: window) } ?? false

        switch action {
        case .restore:
            return nil
        case .previousDisplay, .nextDisplay:
            guard screens.count > 1 else { return nil }
            let order = screens.indices.sorted { screens[$0].frame.minX != screens[$1].frame.minX
                ? screens[$0].frame.minX < screens[$1].frame.minX : screens[$0].frame.minY < screens[$1].frame.minY }
            let position = order.firstIndex(of: index)!
            let offset = action == .nextDisplay ? 1 : order.count - 1
            let target = screens[order[(position + offset) % order.count]]
            // A window where a snap left it takes the same place on the other monitor, gaps and all.
            if let last, last.frame.isClose(to: window), let frame = frame(repeating: last, window: window, in: target, gap: gap) {
                return SnapPlan(frame: frame, action: last.action, step: last.step)
            }
            return SnapPlan(frame: move(window, from: screen.visible, to: target.visible), action: action)
        case .center:
            return SnapPlan(frame: centered(window.size, in: screen.visible), action: action)
        default:
            break
        }

        if repeated, action.isHalf {
            switch repeatMode {
            case .nextDisplay where action == .leftHalf || action == .rightHalf:
                // Like Windows: the window travels across monitors, landing on the near half of the next one.
                guard let next = neighbor(of: index, in: screens, toTheLeft: action == .leftHalf) else { return nil }
                let opposite: SnapAction = action == .leftHalf ? .rightHalf : .leftHalf
                return SnapPlan(frame: frame(for: opposite, in: screens[next], gap: gap), action: opposite)
            case .cycleSizes:
                let step = (last!.step + 1) % halfSteps.count
                return SnapPlan(frame: frame(for: action, in: screen, gap: gap, fraction: halfSteps[step]), action: action, step: step)
            default:
                break
            }
        }
        return SnapPlan(frame: frame(for: action, in: screen, gap: gap), action: action)
    }

    /// The frame of a layout action on a screen. `fraction` is the share of a half's side.
    public static func frame(for action: SnapAction, in screen: SnapScreen, gap: CGFloat, fraction: CGFloat = 0.5) -> CGRect {
        let area = screen.visible
        let third = screen.isPortrait ? area.height / 3 : area.width / 3
        var rect: CGRect = switch action {
        case .leftHalf: CGRect(x: area.minX, y: area.minY, width: area.width * fraction, height: area.height)
        case .rightHalf: CGRect(x: area.maxX - area.width * fraction, y: area.minY, width: area.width * fraction, height: area.height)
        case .topHalf: CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height * fraction)
        case .bottomHalf: CGRect(x: area.minX, y: area.maxY - area.height * fraction, width: area.width, height: area.height * fraction)
        case .topLeft: CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height / 2)
        case .topRight: CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height / 2)
        case .bottomLeft: CGRect(x: area.minX, y: area.midY, width: area.width / 2, height: area.height / 2)
        case .bottomRight: CGRect(x: area.midX, y: area.midY, width: area.width / 2, height: area.height / 2)
        case .firstThird: band(area, from: 0, length: third, portrait: screen.isPortrait)
        case .centerThird: band(area, from: third, length: third, portrait: screen.isPortrait)
        case .lastThird: band(area, from: 2 * third, length: third, portrait: screen.isPortrait)
        case .firstTwoThirds: band(area, from: 0, length: 2 * third, portrait: screen.isPortrait)
        case .lastTwoThirds: band(area, from: third, length: 2 * third, portrait: screen.isPortrait)
        case .maximize, .center, .restore, .previousDisplay, .nextDisplay: area
        }
        rect = rect.wholePoints()
        guard gap > 0 else { return rect }
        // A full gap at the edges of the screen and half of one on each side of an edge shared with a
        // neighbor, so neighbors end up one gap apart.
        func inset(_ edge: CGFloat, _ screenEdge: CGFloat) -> CGFloat { abs(edge - screenEdge) < 1 ? gap : gap / 2 }
        let left = inset(rect.minX, area.minX)
        let right = inset(rect.maxX, area.maxX)
        let top = inset(rect.minY, area.minY)
        let bottom = inset(rect.maxY, area.maxY)
        return CGRect(x: rect.minX + left, y: rect.minY + top, width: rect.width - left - right, height: rect.height - top - bottom).wholePoints()
    }

    /// What a snap did, done again on another screen. Nil for the actions with no place of their own.
    private static func frame(repeating last: SnapRecord, window: CGRect, in screen: SnapScreen, gap: CGFloat) -> CGRect? {
        switch last.action {
        case .restore, .previousDisplay, .nextDisplay:
            nil
        case .center:
            centered(window.size, in: screen.visible)
        default:
            frame(for: last.action, in: screen, gap: gap, fraction: halfSteps.indices.contains(last.step) ? halfSteps[last.step] : 0.5)
        }
    }

    private static func centered(_ size: CGSize, in area: CGRect) -> CGRect {
        let size = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        let origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        return CGRect(origin: origin, size: size).wholePoints()
    }

    /// The screen a window is mostly on, or the one under its center, so a window hanging off every screen
    /// still has one.
    static func screenIndex(for window: CGRect, in screens: [SnapScreen]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.frame.intersection(window)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        if let best { return best.index }
        let center = CGPoint(x: window.midX, y: window.midY)
        let nearest = screens.indices.min { distance(from: center, to: screens[$0].frame) < distance(from: center, to: screens[$1].frame) }
        return nearest
    }

    /// The monitor beside this one, the nearest of those overlapping it vertically, else the nearest at all.
    static func neighbor(of index: Int, in screens: [SnapScreen], toTheLeft: Bool) -> Int? {
        let frame = screens[index].frame
        let candidates = screens.indices.filter { other in
            guard other != index else { return false }
            let otherFrame = screens[other].frame
            return toTheLeft ? otherFrame.maxX <= frame.minX + 1 : otherFrame.minX >= frame.maxX - 1
        }
        func gapTo(_ other: Int) -> CGFloat {
            let otherFrame = screens[other].frame
            return toTheLeft ? frame.minX - otherFrame.maxX : otherFrame.minX - frame.maxX
        }
        func overlaps(_ other: Int) -> Bool {
            let otherFrame = screens[other].frame
            return otherFrame.minY < frame.maxY && otherFrame.maxY > frame.minY
        }
        let beside = candidates.filter(overlaps)
        return (beside.isEmpty ? candidates : beside).min { gapTo($0) < gapTo($1) }
    }

    /// Keeps the window's size, shrunk to fit, and its center at the same share of the visible area. A side
    /// that spans the whole visible area spans the whole of the new one, so a full height window stays one.
    static func move(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        func side(_ length: CGFloat, _ sourceLength: CGFloat, _ targetLength: CGFloat) -> CGFloat {
            length >= sourceLength - tolerance ? targetLength : min(length, targetLength)
        }
        let size = CGSize(width: side(window.width, source.width, target.width), height: side(window.height, source.height, target.height))
        let center = CGPoint(
            x: target.minX + (window.midX - source.minX) / source.width * target.width,
            y: target.minY + (window.midY - source.minY) / source.height * target.height
        )
        let origin = CGPoint(
            x: min(max(center.x - size.width / 2, target.minX), target.maxX - size.width),
            y: min(max(center.y - size.height / 2, target.minY), target.maxY - size.height)
        )
        return CGRect(origin: origin, size: size).wholePoints()
    }

    private static func band(_ area: CGRect, from start: CGFloat, length: CGFloat, portrait: Bool) -> CGRect {
        portrait
            ? CGRect(x: area.minX, y: area.minY + start, width: area.width, height: length)
            : CGRect(x: area.minX + start, y: area.minY, width: length, height: area.height)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

extension CGSize {
    public func isClose(to other: CGSize) -> Bool {
        abs(width - other.width) <= SnapLayout.tolerance && abs(height - other.height) <= SnapLayout.tolerance
    }
}

extension CGRect {
    public func isClose(to other: CGRect) -> Bool {
        abs(minX - other.minX) <= SnapLayout.tolerance && abs(minY - other.minY) <= SnapLayout.tolerance
            && abs(width - other.width) <= SnapLayout.tolerance && abs(height - other.height) <= SnapLayout.tolerance
    }

    /// Whole points, keeping the edges where they round to, so neighbors meet without a seam.
    func wholePoints() -> CGRect {
        let left = minX.rounded()
        let top = minY.rounded()
        return CGRect(x: left, y: top, width: maxX.rounded() - left, height: maxY.rounded() - top)
    }
}
