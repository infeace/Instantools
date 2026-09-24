import AppKit

@main
struct InstantTabApp {
    @MainActor static func main() {
        ensureSingleInstance()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    /// One instance only. A second launch exits quietly, except the copy started by the login agent:
    /// only that one is relaunched after a crash, so it replaces any other copy.
    @MainActor private static func ensureSingleInstance() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).filter { $0 != .current }
        guard !others.isEmpty else { return }
        guard ProcessInfo.processInfo.environment["INSTANTTAB_LAUNCH_AGENT"] == "1" else { exit(0) }
        for other in others { kill(other.processIdentifier, SIGTERM) }
        // Wait for them to restore native Cmd+Tab and release the hotkeys before taking over.
        for _ in 0..<40 where others.contains(where: { kill($0.processIdentifier, 0) == 0 }) {
            usleep(50_000)
        }
    }
}
