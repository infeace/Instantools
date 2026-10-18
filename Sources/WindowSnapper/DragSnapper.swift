import AppKit
import WindowSnapperCore

/// Watches the left mouse button anywhere, through a global monitor, which only listens and needs no
/// permission. Telling a window drag from any other takes AX calls, so they run on the mover's queue: one
/// look at the window under a press, then a few once it starts to drag.
@MainActor
final class DragSnapper {
    private enum Phase {
        case idle
        case pressed(at: CGPoint)
        /// Asking whether the drag moves a window. `start` is where the asking began.
        case probing(start: CGPoint, checks: Int)
        case dragging(windowId: CGWindowID)
        /// Not a window drag, so the rest of it is ignored.
        case ignored
    }

    /// Checks of a drag that has not moved a window yet, before it is taken for something else.
    private static let maxChecks = 8

    var gap: CGFloat = 0
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { start() } else { stop() }
        }
    }

    private let mover: WindowMover
    private let preview = SnapPreview()
    private var monitor: Any?
    private var phase = Phase.idle
    private var isChecking = false
    /// From the mover at every press, so a late answer about an earlier drag is dropped.
    private var press = 0
    private var screens: [SnapScreen] = []
    private var zone: (action: SnapAction, screen: Int)?

    init(mover: WindowMover) {
        self.mover = mover
    }

    private func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            let location = event.cgEvent?.location ?? Screens.pointer()
            MainActor.assumeIsolated { self?.handle(type, at: location) }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        finish(at: nil)
    }

    private func handle(_ type: NSEvent.EventType, at point: CGPoint) {
        switch type {
        case .leftMouseDown:
            finish(at: nil)
            let press = mover.notePress()
            self.press = press
            phase = .pressed(at: point)
            mover.queue.async { [mover] in mover.beginDrag(at: point, press: press) }
        case .leftMouseDragged:
            dragged(to: point)
        case .leftMouseUp:
            finish(at: point)
        default:
            break
        }
    }

    private func dragged(to point: CGPoint) {
        switch phase {
        case .pressed(let start):
            guard hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
            phase = .probing(start: point, checks: 0)
            screens = Screens.current()
        case .probing(let start, _):
            guard !isChecking, hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
            isChecking = true
            let press = press
            mover.queue.async { [weak self, mover] in
                let result = mover.checkDrag(pointer: point, press: press)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.checked(result, press: press) } }
            }
        case .dragging:
            updateZone(at: point)
        case .idle, .ignored:
            break
        }
    }

    private func checked(_ result: WindowMover.DragCheck, press: Int) {
        guard press == self.press else { return }
        isChecking = false
        guard case .probing(let start, let checks) = phase else { return }
        switch result {
        case .moving(let windowId):
            phase = .dragging(windowId: windowId)
            updateZone(at: Screens.pointer())
        case .notYet:
            phase = checks + 1 >= Self.maxChecks ? .ignored : .probing(start: start, checks: checks + 1)
        case .notAWindowDrag:
            phase = .ignored
        }
    }

    private func updateZone(at point: CGPoint) {
        guard case .dragging(let windowId) = phase else { return }
        let found = SnapZones.action(at: point, screens: screens)
        guard found?.action != zone?.action || found?.screen != zone?.screen else { return }
        zone = found
        if let found {
            preview.show(frame(of: found), below: windowId)
        } else {
            preview.hide()
        }
    }

    /// Ends the drag, snapping the window when the button came up over a zone. `point` is nil when the drag
    /// was cut short. A drag still being checked snaps too, if the mover finds the window moved: a quick
    /// flick can end before the first answer.
    private func finish(at point: CGPoint?) {
        var target: (action: SnapAction, frame: CGRect)?
        if let point {
            switch phase {
            case .dragging:
                // The release can come without a last move to it.
                updateZone(at: point)
                target = zone.map { ($0.action, frame(of: $0)) }
            case .probing:
                target = SnapZones.action(at: point, screens: screens).map { ($0.action, frame(of: $0)) }
            case .idle, .pressed, .ignored:
                break
            }
        }
        let pressed = if case .idle = phase { false } else { true }
        phase = .idle
        zone = nil
        isChecking = false
        preview.hide()
        guard pressed else { return }
        mover.queue.async { [mover, target] in mover.endDrag(snapTo: target) }
    }

    private func frame(of zone: (action: SnapAction, screen: Int)) -> CGRect {
        SnapLayout.frame(for: zone.action, in: screens[zone.screen], gap: gap)
    }
}
