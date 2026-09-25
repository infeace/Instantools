import AppKit
import InstantoolsCore
import InstantoolsKit
import LayoutSwitcherCore

@MainActor
final class LayoutSwitcherDelegate: NSObject, NSApplicationDelegate {
    private let sources = InputSources()
    private let tap = ChordTap()
    private var permissionPoll: Timer?
    private lazy var channel = ToolChannel { [unowned self] request in
        switch request.request {
        case .status: ToolMessage(id: request.id, layoutSwitcher: LayoutSwitcherStatus(tapRunning: tap.isRunning, layouts: sources.names))
        }
    }
    /// Keeps App Nap from delaying the tap callback.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Layout switches must be instant"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.log.notice("launched")
        tap.onChord = { [unowned self] in sources.switchLayout() }
        startTap()

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tap.recover() }
            }
        }
        channel.start()
    }

    /// Asks once. The system prompt shows only the first time, so Settings in the host offers it again.
    private func startTap() {
        if tap.start() { return }
        if ProcessInfo.processInfo.environment[ToolLaunch.askInputMonitoringKey] != "0" { Permissions.requestInputMonitoring() }
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tap.start() else { return }
                self.permissionPoll?.invalidate()
                self.permissionPoll = nil
                Diagnostics.log.notice("permission granted, event tap running")
            }
        }
    }
}
