import AppKit
import QuartzCore

/// Measures key press to first displayed frame: after the panel is ordered in, the next display link
/// tick's target timestamp is when the panel reaches the screen.
@MainActor
final class FrameProbe: NSObject {
    private let view: NSView
    private var link: CADisplayLink?
    private var startNanoseconds: UInt64?
    var onMeasured: ((UInt64) -> Void)?

    init(view: NSView) {
        self.view = view
    }

    /// The link follows the view to whichever display it is on.
    func arm(startNanoseconds: UInt64) {
        self.startNanoseconds = startNanoseconds
        if link == nil {
            link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        }
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        link.isPaused = true
        guard let start = startNanoseconds else { return }
        startNanoseconds = nil
        let frame = UInt64(max(link.targetTimestamp, 0) * 1_000_000_000)
        if frame > start { onMeasured?(frame - start) }
    }
}
