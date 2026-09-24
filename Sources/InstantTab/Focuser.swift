import AppKit
import InstantTabCore
import SkyLightShim
import os

final class Focuser: Sendable {
    private let queue = DispatchQueue(label: "com.infeace.InstantTab.focus", qos: .userInteractive)
    /// Raising talks to the target app and can stall, so it never holds up the next focus.
    private let raiseQueue = DispatchQueue(label: "com.infeace.InstantTab.raise", qos: .userInteractive, attributes: .concurrent)
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    /// `closingExpose` is set after InstantTab opened App Exposé, which would otherwise stay over the app.
    func focus(_ entry: SwitcherEntry, closingExpose: Bool = false) {
        let token = nextToken()
        // Accessibility calls into this process run AppKit on the calling thread, which crashes off main,
        // so InstantTab's own windows are brought forward with AppKit.
        if entry.pid == ownPid {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.focusOwnWindow(entry.windowId) }
            }
        } else {
            queue.async { [self] in perform(entry, token: token) }
        }
        // After the switch, so App Exposé closes onto the new app instead of the one it was showing.
        if closingExpose { queue.async { Self.closeExpose() } }
    }

    /// For an app key whose app is not running. Opening it cancels any focus still in flight.
    func launch(bundleId: String, closingExpose: Bool = false) {
        _ = nextToken()
        queue.async {
            defer { if closingExpose { Self.closeExpose() } }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                return DispatchQueue.main.async { NSSound.beep() }
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Only while App Exposé is still up, since the toggle would otherwise open it again.
    private static func closeExpose() {
        if WindowTracker.dockOverlayIsUp() { SkyLight.toggleAppExpose() }
    }

    private func nextToken() -> Int {
        generation.withLock { value in
            value += 1
            return value
        }
    }

    @MainActor private static func focusOwnWindow(_ windowId: UInt32?) {
        if NSApp.isHidden { NSApp.unhide(nil) }
        let window = windowId.flatMap { NSApp.window(withWindowNumber: Int($0)) }
            ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey && $0.level == .normal }
        OwnWindow.bringForward(window)
    }

    private func isCurrent(_ token: Int) -> Bool {
        generation.withLock { $0 == token }
    }

    private func perform(_ entry: SwitcherEntry, token: Int) {
        guard isCurrent(token), let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        if app.isHidden { app.unhide() }

        // No visible window (none open, minimized, or on another Space): open the app like a Dock click.
        // That activates it, switches to its Space, restores a minimized window, and has an app with no
        // window, like Finder, open one, as AltTab does.
        guard let windowId = entry.windowId else {
            guard let url = app.bundleURL else { return activate(app, token: token) }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [self] _, error in
                if error != nil { activate(app, token: token) }
            }
            return
        }
        guard SkyLight.focus(pid: entry.pid, windowId: windowId) else { return activate(app, token: token) }
        guard AXIsProcessTrusted() else { return }
        raiseQueue.async { [self] in
            guard isCurrent(token) else { return }
            raise(windowId, of: entry.pid)
        }
    }

    /// macOS can decline an activation and still report success, so this checks that it happened.
    private func activate(_ app: NSRunningApplication, token: Int) {
        app.activate(options: .activateAllWindows)
        queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [self] in
            guard isCurrent(token), !app.isActive else { return }
            SkyLight.focus(pid: app.processIdentifier, windowId: 0)
        }
    }

    /// The front-process call alone does not reorder an app's own windows.
    private func raise(_ windowId: UInt32, of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let window = windows.first(where: { SkyLight.windowId(of: $0) == windowId })
        else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
