import AppKit

@main
struct InstantTabApp {
    @MainActor static func main() {
        SettingsSnapshot.runIfRequested()
        ensureSingleInstance()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // LSUIElement already does this in the bundle; this covers an unbundled `swift run`.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    /// A second launch exits quietly, except the copy started by the login agent: only that one is
    /// relaunched after a crash, so it replaces any other.
    @MainActor private static func ensureSingleInstance() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0 != .current }
            .map(\.processIdentifier)
            .filter { $0 > 0 }
        guard !others.isEmpty else { return }
        guard LoginItem.isSupervised else { exit(0) }
        func alive() -> [pid_t] { others.filter { kill($0, 0) == 0 } }
        for pid in others { kill(pid, SIGTERM) }
        // Give them time to restore native Cmd+Tab and release the hotkeys. One that hangs is killed,
        // otherwise its later exit would turn native Cmd+Tab back on underneath this copy.
        for _ in 0..<40 where !alive().isEmpty { usleep(50_000) }
        for pid in alive() { kill(pid, SIGKILL) }
    }
}
