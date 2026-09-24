import AppKit
import QuartzCore

/// Measures key press to first displayed frame: after the panel is ordered in, the next display link
/// tick's target timestamp is when the panel reaches the screen.
@MainActor
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var linkedView: NSView?
    private var startNanoseconds: UInt64?
    var onMeasured: ((UInt64) -> Void)?

    func arm(view: NSView, startNanoseconds: UInt64) {
        self.startNanoseconds = startNanoseconds
        if linkedView !== view {
            link?.invalidate()
            link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
            linkedView = view
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
