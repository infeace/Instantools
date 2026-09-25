import AppKit
import InstantoolsCore
import InstantoolsKit

@MainActor
final class LayoutSwitcherDelegate: NSObject, NSApplicationDelegate {
    private let sources = InputSources()
    private let tap = ChordTap()
    private lazy var tapPoll = PermissionPoll(
        allowed: { Permissions.inputMonitoring }, start: { [unowned self] in tap.start() }, thenLog: "permission granted, event tap running"
    )
    private lazy var channel = ToolChannel { [unowned self] request in
        switch request.request {
        case .status: ToolMessage(layoutSwitcher: LayoutSwitcherStatus(tapRunning: tap.isRunning))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.log.notice("launched")
        tap.onChord = { [unowned self] in sources.switchLayout() }
        startTap()

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.tapPoll.isPolling else { return }
                    if !self.tap.recover() { self.tapPoll.run() }
                }
            }
        }
        channel.start()
    }

    /// Asks once. The system prompt shows only the first time, so Settings in the host offers it again.
    private func startTap() {
        if tap.start() { return }
        if ProcessInfo.processInfo.environment[ToolLaunch.askInputMonitoringKey] != "0" { Permissions.requestInputMonitoring() }
        tapPoll.run()
    }
}
