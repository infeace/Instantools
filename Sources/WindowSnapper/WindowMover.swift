import ApplicationServices
import InstantoolsKit
import os
import SkyLightShim
import WindowSnapperCore

/// Moves windows, by shortcut and by drag. Every AX call runs on `queue`, so a busy app never holds up the
/// main thread, which answers hotkeys, mouse moves and the host's pings. All state is only touched there.
final class WindowMover: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.infeace.Instantools.snap", qos: .userInteractive)

    enum DragCheck: Sendable {
        /// A window is being dragged by its title bar. Its WindowServer id, or 0 when it could not be read.
        case moving(windowId: CGWindowID)
        /// Nothing has moved yet. A drag that never moves a window is a text selection or the like.
        case notYet
        case notAWindowDrag
    }

    private struct Drag {
        let window: AXUIElement
        let app: AXUIElement
        /// The frame and the pointer when the button went down.
        let start: CGRect
        let pointer: CGPoint
        var isMoving = false
        /// Where restore takes the window after it is dropped on a zone.
        var previous: CGRect
    }

    private var memory = SnapMemory()
    private var drag: Drag?
    /// The latest press, set on the main thread, so a press already followed by another is not looked at: an
    /// app that is not answering would otherwise hold the queue for each click on it.
    private let latestPress = OSAllocatedUnfairLock(initialState: 0)

    /// On the main thread, at every press. The number it returns goes with that press's calls.
    func notePress() -> Int {
        latestPress.withLock { press in
            press += 1
            return press
        }
    }

    private func isCurrent(_ press: Int) -> Bool {
        latestPress.withLock { $0 == press }
    }

    func snapFocused(_ action: SnapAction, frontmost: pid_t?, screens: [SnapScreen], repeatMode: RepeatMode, gap: CGFloat) {
        guard let (window, app) = AXWindows.focusedWindow(frontmost: frontmost), let frame = AXWindows.frame(of: window) else {
            Diagnostics.log.notice("no focused window to snap in pid \(frontmost ?? 0)")
            return
        }
        let ref = WindowRef(element: window)
        if action == .restore {
            guard let snapped = memory.remove(ref) else { return }
            AXWindows.setFrame(snapped.previous, of: window, app: app)
            return
        }
        let last = memory[ref]
        guard let plan = SnapLayout.plan(action, window: frame, screens: screens, last: last?.record, repeatMode: repeatMode, gap: gap) else {
            return
        }
        // A window still where the last snap left it keeps the frame it had before the first one.
        let previous = last.flatMap { $0.record.frame.isClose(to: frame) ? $0.previous : nil } ?? frame
        let landed = AXWindows.setFrame(plan.frame, of: window, app: app) ?? plan.frame
        memory.set(.init(previous: previous, record: SnapRecord(action: plan.action, step: plan.step, frame: landed)), for: ref)
    }

    /// On every press, since the frame must be read before anything moves: a quick flick to an edge can end
    /// before a drag is noticed. The pointer is on what may be dragged, which for a window drag is its title bar.
    func beginDrag(at pointer: CGPoint, press: Int) {
        drag = nil
        guard isCurrent(press), let (window, app) = AXWindows.window(at: pointer), AXWindows.isMovable(window),
              let frame = AXWindows.frame(of: window)
        else { return }
        drag = Drag(window: window, app: app, start: frame, pointer: pointer, previous: frame)
    }

    /// A window drag moves the window and keeps its size. One that was snapped and not resized since goes
    /// back to its size from before, staying under the pointer at the same share of its width.
    func checkDrag(pointer: CGPoint, press: Int) -> DragCheck {
        guard isCurrent(press), var drag else { return .notAWindowDrag }
        if drag.isMoving { return .moving(windowId: SkyLight.windowId(of: drag.window) ?? 0) }
        guard let frame = AXWindows.frame(of: drag.window) else {
            self.drag = nil
            return .notAWindowDrag
        }
        switch SnapDrag.classify(start: drag.start, now: frame) {
        case .notYet:
            return .notYet
        case .other:
            self.drag = nil
            return .notAWindowDrag
        case .moving:
            break
        }
        drag.isMoving = true
        let ref = WindowRef(element: drag.window)
        if let snapped = memory[ref], snapped.record.frame.size.isClose(to: drag.start.size) {
            memory.remove(ref)
            let restored = SnapDrag.unsnapped(frame, grabbedAt: drag.pointer, start: drag.start, previousSize: snapped.previous.size, pointer: pointer)
            AXWindows.setSize(restored.size, of: drag.window)
            AXWindows.setPosition(restored.origin, of: drag.window)
            drag.previous = snapped.previous
        }
        self.drag = drag
        return .moving(windowId: SkyLight.windowId(of: drag.window) ?? 0)
    }

    /// The button is up. `target` is the zone it was released over, if any.
    func endDrag(snapTo target: (action: SnapAction, frame: CGRect)?) {
        defer { drag = nil }
        guard let drag, let target else { return }
        let ref = WindowRef(element: drag.window)
        var previous = drag.previous
        // A flick can be over before any check ran, so the last look decides.
        if !drag.isMoving {
            guard let frame = AXWindows.frame(of: drag.window), SnapDrag.classify(start: drag.start, now: frame) == .moving else { return }
            // Never unsnapped on the way, so a window a snap left there keeps its frame from before that snap.
            if let snapped = memory[ref], snapped.record.frame.isClose(to: drag.start) { previous = snapped.previous }
        }
        let landed = AXWindows.setFrame(target.frame, of: drag.window, app: drag.app) ?? target.frame
        memory.set(.init(previous: previous, record: SnapRecord(action: target.action, frame: landed)), for: ref)
    }
}

/// What InstantSnap did to recent windows, for restore and for a shortcut pressed again. Kept for the last
/// windows only, since a closed window is never heard of again.
struct SnapMemory {
    struct Entry {
        /// The frame before the first of the snaps that left the window where it is.
        var previous: CGRect
        var record: SnapRecord
    }

    private static let limit = 100
    private var entries: [WindowRef: Entry] = [:]
    private var order: [WindowRef] = []

    subscript(ref: WindowRef) -> Entry? {
        entries[ref]
    }

    mutating func set(_ entry: Entry, for ref: WindowRef) {
        if entries[ref] == nil {
            order.append(ref)
            if order.count > Self.limit { entries[order.removeFirst()] = nil }
        }
        entries[ref] = entry
    }

    @discardableResult
    mutating func remove(_ ref: WindowRef) -> Entry? {
        order.removeAll { $0 == ref }
        return entries.removeValue(forKey: ref)
    }
}
