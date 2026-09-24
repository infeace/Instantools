import AppKit
import SkyLightShim

/// Brings one of InstantTab's own windows to the front. Since macOS 14, `NSApp.activate()` from a menu
/// bar app is only a request that the frontmost app can decline, so InstantTab also makes itself the
/// front process directly, the same way the switcher focuses other apps.
@MainActor
enum OwnWindow {
    static func bringForward(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        SkyLight.focus(pid: ProcessInfo.processInfo.processIdentifier, windowId: CGWindowID(window.windowNumber))
    }
}
