import AppKit
import InstantTabCore
import SkyLightShim
import os

final class Focuser: Sendable {
    private let queue = DispatchQueue(label: "com.infeace.InstantTab.focus", qos: .userInteractive)
    /// Raising talks to the target app and can stall, so it never holds up the next focus.
    private let raiseQueue = DispatchQueue(label: "com.infeace.InstantTab.raise", qos: .userInteractive, attributes: .concurrent)
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    func focus(_ entry: SwitcherEntry) {
        let token = generation.withLock { value in
            value += 1
            return value
        }
        // Accessibility calls into this process run AppKit on the calling thread, which crashes off main,
        // so InstantTab's own windows are brought forward with AppKit.
        guard entry.pid != ownPid else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.focusOwnWindow(entry.windowId) }
            }
            return
        }
        queue.async { [self] in perform(entry, token: token) }
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

        // No visible window (windowless, minimized, or on another Space): activate like native, which
        // also switches to the app's Space.
        guard let windowId = entry.windowId else {
            app.activate(options: .activateAllWindows)
            // macOS can decline the activation and still report success, so check that it happened.
            queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [self] in
                guard isCurrent(token), !app.isActive else { return }
                SkyLight.focus(pid: entry.pid, windowId: 0)
            }
            return
        }
        guard SkyLight.focus(pid: entry.pid, windowId: windowId) else {
            app.activate()
            return
        }
        guard AXIsProcessTrusted() else { return }
        raiseQueue.async { [self] in
            guard isCurrent(token) else { return }
            raise(windowId, of: entry.pid)
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
