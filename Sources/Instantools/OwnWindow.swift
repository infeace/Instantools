import AppKit
import SkyLightShim

/// Since macOS 14, `NSApp.activate()` from a menu bar app is a request the frontmost app can decline,
/// so Instantools also makes itself the front process directly, as the switcher does for other apps.
@MainActor
enum OwnWindow {
    static func bringForward(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        SkyLight.focus(pid: ownPid, windowId: CGWindowID(window.windowNumber))
    }
}

let ownPid = ProcessInfo.processInfo.processIdentifier
