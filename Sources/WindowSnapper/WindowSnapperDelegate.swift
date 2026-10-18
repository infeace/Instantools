import AppKit
import InstantoolsCore
import InstantoolsKit
import WindowSnapperCore

@MainActor
final class WindowSnapperDelegate: NSObject, NSApplicationDelegate {
    /// Read only: Settings in the host writes the file, and every change reaches this copy through the file.
    private let configStore = ConfigFileStore<SnapConfig>(persists: false)
    private let mover = WindowMover()
    private let hotKeys = SnapHotKeys()
    private lazy var dragSnapper = DragSnapper(mover: mover)
    private var config = SnapConfig()
    private lazy var channel = ToolChannel { [unowned self] in
        ToolMessage(windowSnapper: WindowSnapperStatus(
            accessibility: AXIsProcessTrusted(), unavailableShortcuts: hotKeys.unavailable.map(\.text)
        ))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A hung app would otherwise hold the mover's queue for the 6s default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        Diagnostics.log.notice("launched")
        hotKeys.onPress = { [weak self] action in self?.snap(action) }
        configStore.onChange = { [weak self] config in self?.apply(config) }
        configStore.start()
        apply(configStore.config)

        // A shortcut another app held, such as Rectangle, is free once that app quits.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.hotKeys.unavailable.isEmpty else { return }
                self.hotKeys.unregister()
                self.hotKeys.register(self.config.boundShortcuts)
            }
        }
        if !AXIsProcessTrusted(), ProcessInfo.processInfo.environment[ToolLaunch.askAccessibilityKey] != "0" {
            Permissions.requestAccessibility()
        }
        channel.start()
    }

    private func apply(_ config: SnapConfig) {
        self.config = config
        hotKeys.register(config.boundShortcuts)
        dragSnapper.gap = CGFloat(config.gap)
        dragSnapper.isEnabled = config.dragToSnap
    }

    private func snap(_ action: SnapAction) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let screens = Screens.current()
        let repeatMode = config.repeatMode
        let gap = CGFloat(config.gap)
        mover.queue.async { [mover] in
            mover.snapFocused(action, frontmost: frontmost, screens: screens, repeatMode: repeatMode, gap: gap)
        }
    }
}
