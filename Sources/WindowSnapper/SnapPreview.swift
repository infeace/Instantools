import AppKit

/// Where a dragged window will land, drawn the moment the pointer reaches a zone. Created once and reused:
/// showing it only sets a frame and a layer's colors, with no animation.
@MainActor
final class SnapPreview {
    private let panel: NSPanel
    private let box = CALayer()
    /// Whether this Mac lets the preview go just behind the dragged window, as macOS draws its own. Learned
    /// on the first drag; otherwise it floats above, see-through.
    private var canOrderBelow: Bool?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.canHide = false

        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(box)
        panel.contentView = view
        box.cornerRadius = 16
        box.cornerCurve = .continuous
        box.borderWidth = 2
    }

    /// `frame` in AX coordinates.
    func show(_ frame: CGRect, below windowId: CGWindowID) {
        let rect = Screens.appKitFrame(frame)
        panel.setFrame(rect, display: false)
        let accent = NSColor.controlAccentColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.frame = CGRect(origin: .zero, size: rect.size)
        box.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        box.borderColor = accent.withAlphaComponent(0.7).cgColor
        CATransaction.commit()

        guard windowId != 0, canOrderBelow != false else { return floatAbove() }
        panel.level = .normal
        panel.order(.below, relativeTo: Int(windowId))
        if canOrderBelow == nil {
            canOrderBelow = isJustBelow(windowId)
            if canOrderBelow == false { floatAbove() }
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func floatAbove() {
        panel.level = .floating
        panel.orderFrontRegardless()
    }

    /// Window numbers need no Screen Recording permission. The dragged app's own child windows, such as a
    /// sheet, may sit between.
    private func isJustBelow(_ windowId: CGWindowID) -> Bool {
        guard let below = CGWindowListCopyWindowInfo([.optionOnScreenBelowWindow], windowId) as? [[String: Any]] else {
            return false
        }
        let own = panel.windowNumber
        return below.prefix(3).contains { ($0[kCGWindowNumber as String] as? Int) == own }
    }
}
