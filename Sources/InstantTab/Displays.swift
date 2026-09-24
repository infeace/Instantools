import AppKit
import InstantTabCore

/// The connected displays, refreshed when the arrangement changes. Nothing here is tied to a
/// specific setup: displays are re-read on every connect, disconnect or rearrangement.
@MainActor
final class Displays {
    private(set) var displays: [Display] = []
    private var screensById: [UInt32: NSScreen] = [:]
    var onChange: (() -> Void)?

    func start() {
        reload()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
                self?.onChange?()
            }
        }
    }

    private func reload() {
        var list: [Display] = []
        var byId: [UInt32: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            list.append(Display(id: id, frame: CGDisplayBounds(id)))
            byId[id] = screen
        }
        displays = list
        screensById = byId
    }

    /// The display under the mouse pointer.
    func mouseDisplayId() -> UInt32? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
        return screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func screen(for id: UInt32?) -> NSScreen? {
        id.flatMap { screensById[$0] } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
