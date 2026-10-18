import AppKit

/// Settings and the welcome window send the user to System Settings to allow a permission or change a
/// setting. Closing its window quits it, and on its death WindowServer brings forward an app of its own choice,
/// not Instantools, so Instantools ends up behind that app. So when System Settings was opened from
/// Instantools and quits, Instantools comes back to the front at once, watching the process itself, since
/// the workspace notifications arrive later. Switching to another app while System Settings is still open is
/// left alone.
@MainActor
final class SystemSettingsReturn {
    private static let bundleId = "com.apple.systempreferences"

    var onReturn: (() -> Void)?
    private var lastActive: pid_t?
    /// System Settings, while it is in front after Instantools was.
    private var armed: NSRunningApplication?
    private var exitWatch: DispatchSourceProcess?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
    }

    private func activated(_ app: NSRunningApplication?) {
        guard let app else { return }
        let previous = lastActive
        lastActive = app.processIdentifier
        if app.bundleIdentifier == Self.bundleId {
            if previous == ownPid, armed == nil { arm(app) }
            return
        }
        guard let armed else { return }
        if app.processIdentifier == ownPid || Self.hasWindowOnScreen(armed.processIdentifier) {
            disarm()
        } else if armed.isTerminated {
            comeBack()
        } else {
            // WindowServer's pick as System Settings quits, or the user went to another Space, which hides its
            // window just the same. Only quitting ends in an exit, so that is waited for, briefly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated {
                    if self?.armed == armed { self?.disarm() }
                }
            }
        }
    }

    private func arm(_ settings: NSRunningApplication) {
        armed = settings
        let watch = DispatchSource.makeProcessSource(identifier: settings.processIdentifier, eventMask: .exit, queue: .main)
        watch.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.comeBack() }
        }
        watch.resume()
        exitWatch = watch
    }

    private func comeBack() {
        guard armed != nil else { return }
        disarm()
        onReturn?()
    }

    private func disarm() {
        exitWatch?.cancel()
        exitWatch = nil
        armed = nil
    }

    private static func hasWindowOnScreen(_ pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { window in
            (window[kCGWindowOwnerPID as String] as? pid_t) == pid && (window[kCGWindowLayer as String] as? Int) == 0
        }
    }
}
