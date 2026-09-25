import AppKit
import AppSwitcherCore
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit
import SkyLightShim

@MainActor
final class AppSwitcherDelegate: NSObject, NSApplicationDelegate {
    /// Read only: Settings in the host writes the file, and every change reaches this copy through the file.
    private let configStore = ConfigStore(persists: false)
    private let displays = Displays()
    private let icons = IconCache()
    private lazy var tracker = WindowTracker(displays: displays)
    private lazy var taps: InputTaps = InputTaps(
        onCommandReleased: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.controller.commandReleased() } }
        },
        onSessionKey: { [weak self] key in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.controller.sessionKey(key) } }
        }
    )
    private lazy var controller: SwitcherController = SwitcherController(tracker: tracker, displays: displays, icons: icons, taps: taps)
    private let hotKeys = HotKeys()
    private var permissionPoll: Timer?
    private var handlesCmdTab = false
    private var passThrough = BundleIdMatcher([])
    private var hostObservation: NSKeyValueObservation?
    private lazy var channel = ToolChannel { [unowned self] request in
        switch request.request {
        case .status: ToolMessage(id: request.id, appSwitcher: status())
        }
    }
    /// Keeps App Nap from stretching the show delay and release timers.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Cmd+Tab must respond instantly"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeSwitcher.installExitHandlers()
        // Raises run on their own queue, but a hung app would otherwise pin a thread for the 6s default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        Diagnostics.log.notice("launched, SkyLight focus available: \(SkyLight.canFocusWindows)")

        displays.start()
        displays.onChange = { [weak self] in
            self?.controller.resolveGroups()
            self?.tracker.refreshWindows()
        }
        hotKeys.onPress = { [weak self] action, eventNanoseconds in
            self?.controller.hotKeyPressed(action, eventNanoseconds: eventNanoseconds)
        }
        // Before the config loads, so a pass-through app already in front gets its Cmd+Tab back.
        handlesCmdTab = takeOver()
        configStore.onChange = { [weak self] config in
            guard let self else { return }
            icons.setIconSize(config.iconSize)
            controller.config = config
            passThrough = BundleIdMatcher(config.passThrough)
            applyPassThrough()
        }
        configStore.start()
        tracker.onChange = { [weak self] in
            guard let self else { return }
            icons.sync(with: tracker.snapshot.apps.map(\.pid))
            controller.modelChanged()
        }
        tracker.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.applyPassThrough(front: app) }
        }
        observeHost()
        startTaps()
        controller.warmUp()
        channel.start()
    }

    /// Native Cmd+Tab goes off only once the hotkeys are registered, so a failure never leaves the Mac
    /// without one. If it cannot go off, it would win over the hotkeys, so the status reports macOS kept it.
    private func takeOver() -> Bool {
        guard hotKeys.register() else {
            NativeSwitcher.restore()
            Diagnostics.log.error("could not register Cmd+Tab, native switcher left on")
            return false
        }
        guard NativeSwitcher.disable() else {
            hotKeys.unregister()
            NativeSwitcher.restore()
            Diagnostics.log.error("could not turn off native Cmd+Tab, native switcher left on")
            return false
        }
        return true
    }

    /// While a pass-through app is in front, the hotkeys are let go with native Cmd+Tab still off, so the key
    /// reaches that app. Registering and unregistering do nothing when already done.
    private func applyPassThrough(front: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard handlesCmdTab else { return }
        if passThrough.matches(front?.bundleIdentifier) {
            hotKeys.unregister()
        } else if !hotKeys.register() {
            // Without the hotkeys and with native Cmd+Tab off, the Mac would have no switcher at all.
            NativeSwitcher.restore()
            handlesCmdTab = false
            Diagnostics.log.error("could not take Cmd+Tab back from a pass-through app, native switcher restored")
        }
    }

    /// The host becomes a regular app while its Settings window is open, which no workspace notification
    /// reports, so the list follows its activation policy directly.
    private func observeHost() {
        hostObservation = NSRunningApplication(processIdentifier: getppid())?.observe(\.activationPolicy) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.tracker.reload() }
            }
        }
    }

    private func startTaps() {
        if Permissions.accessibility, taps.start() { return }

        // Until Accessibility is granted, releases are caught by polling and the in-switcher keys do nothing.
        Permissions.requestAccessibility()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard Permissions.accessibility, let self, self.taps.start() else { return }
                self.permissionPoll?.invalidate()
                self.permissionPoll = nil
                Diagnostics.log.notice("accessibility granted, input taps running")
            }
        }
    }

    private func status() -> AppSwitcherStatus {
        AppSwitcherStatus(
            latencySamples: controller.latency.chronological,
            focusedDisplay: DisplayScope.focusedDisplay(
                in: tracker.snapshot, frontmostPid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                displays: displays.displays
            ),
            recentApps: controller.previewEntries().prefix(8).map { entry in
                AppSwitcherStatus.RecentApp(
                    pid: entry.pid, name: entry.name, hasWindow: entry.windowId != nil, isHidden: entry.isHidden,
                    key: entry.key.map(String.init)
                )
            },
            tapsRunning: taps.isRunning,
            handlesCmdTab: handlesCmdTab
        )
    }
}
