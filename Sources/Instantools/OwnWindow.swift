import AppKit
import SkyLightShim

/// Since macOS 14, `NSApp.activate()` from a menu bar app is a request the frontmost app can decline,
/// so Instantools also makes itself the front process directly, as the switcher does for other apps.
@MainActor
enum OwnWindow {
    /// Instantools is a regular app while any of its windows is open, so Cmd+Tab reaches them.
    private static var open: Set<ObjectIdentifier> = []

    static func opened(_ window: NSWindow) {
        open.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
    }

    static func closed(_ window: NSWindow) {
        open.remove(ObjectIdentifier(window))
        if open.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    static func present(_ window: NSWindow) {
        bringForward(window)
        // Right after becoming a regular app the first request can be dropped.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !NSApp.isActive || !window.isKeyWindow { bringForward(window) }
            }
        }
    }

    private static func bringForward(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        SkyLight.focus(pid: ownPid, windowId: CGWindowID(window.windowNumber))
    }
}

let ownPid = ProcessInfo.processInfo.processIdentifier
