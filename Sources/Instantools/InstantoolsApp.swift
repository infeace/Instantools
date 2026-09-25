import AppKit
import InstantoolsCore

@main
struct InstantoolsApp {
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
        // Longer than a host takes to stop its tools, which restore native Cmd+Tab and release the hotkeys.
        // Tools of one that hangs and is killed are found and stopped at launch, before this copy starts its own.
        LeftoverProcesses.terminate(others, timeout: ToolLaunch.stopTimeout + 1)
    }
}
