import AppKit
import InstantTabCore
import SkyLightShim
import os

/// Brings the chosen app or window forward off the main thread. A newer request supersedes an older one.
final class Focuser: Sendable {
    private let queue = DispatchQueue(label: "com.infeace.InstantTab.focus", qos: .userInteractive)
    /// Raising talks to the target app and can stall, so it runs apart from the next focus request.
    private let raiseQueue = DispatchQueue(label: "com.infeace.InstantTab.raise", qos: .userInteractive, attributes: .concurrent)
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    func focus(_ entry: SwitcherEntry) {
        let token = generation.withLock { value in
            value += 1
            return value
        }
        queue.async { [self] in perform(entry, token: token) }
    }

    private func isCurrent(_ token: Int) -> Bool {
        generation.withLock { $0 == token }
    }

    private func perform(_ entry: SwitcherEntry, token: Int) {
        guard isCurrent(token), let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        if app.isHidden { app.unhide() }

        // No visible window (windowless, minimized, or only on another Space): activate like native,
        // which also switches to the app's Space.
        guard let windowId = entry.windowId else {
            if !app.activate(options: .activateAllWindows) { SkyLight.focus(pid: entry.pid, windowId: 0) }
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

    /// Puts the window on top of its app's other windows. The front-process call alone does not reorder them.
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
