import AppKit
import InstantTabCore
import SkyLightShim

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    private let displays = Displays()
    private let icons = IconCache()
    private lazy var tracker = WindowTracker(displays: displays)
    private lazy var controller = SwitcherController(tracker: tracker, displays: displays, icons: icons)
    private let hotKeys = HotKeys()
    private var taps: InputTaps?
    private var permissionPoll: Timer?
    private var statusItem: NSStatusItem?
    private var isPaused = false
    private lazy var settings = SettingsWindowController(
        makeModel: { [unowned self] in
            SettingsModel(configStore: configStore, actions: .init(
                isPaused: { [unowned self] in isPaused },
                setPaused: { [unowned self] paused in setPaused(paused) },
                latency: { [unowned self] in controller.latency },
                displays: { [unowned self] in displays.displays },
                mouseDisplay: { [unowned self] in displays.mouseDisplayId() },
                accessibilityGranted: { Permissions.accessibility },
                recentApps: { [unowned self] in previewApps() }
            ))
        },
        onOpenChange: { [unowned self] in tracker.reload() }
    )
    /// Keeps App Nap from stretching the show delay and release timers.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Cmd+Tab must respond instantly"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeSwitcher.installExitHandlers()
        // A hung app must never hold up focusing.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        Diagnostics.log.notice("launched \(Bundle.main.shortVersion, privacy: .public), SkyLight focus available: \(SkyLight.canFocusWindows)")

        displays.start()
        displays.onChange = { [weak self] in
            self?.controller.resolveGroups()
            self?.tracker.refreshWindows()
        }
        configStore.onChange = { [weak self] config in self?.controller.config = config }
        configStore.start()
        tracker.onChange = { [weak self] in
            guard let self else { return }
            icons.sync(with: tracker.snapshot.apps.map(\.pid))
            controller.modelChanged()
        }
        tracker.start()

        hotKeys.onPress = { [weak self] action, eventNanoseconds in
            self?.controller.hotKeyPressed(action, eventNanoseconds: eventNanoseconds)
        }
        isPaused = !takeOver()
        startTaps()
        controller.warmUp()
        LoginItem.repairIfMoved()
        NSApp.mainMenu = makeMainMenu()
        statusItem = makeStatusItem()

        NativeSwitcher.beforeSignalExit = { [unowned self] in
            configStore.flush()
            if settings.isOpen { Handoff.markSettingsOpen() }
        }
        if Handoff.consumeSettingsOpen() { settings.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        configStore.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    /// Native Cmd+Tab goes off only once the hotkeys are registered, so a failure never leaves the Mac
    /// without one.
    private func takeOver() -> Bool {
        guard hotKeys.register() else {
            NativeSwitcher.restore()
            Diagnostics.log.error("could not register Cmd+Tab, native switcher left on")
            return false
        }
        NativeSwitcher.disable()
        return true
    }

    private func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        if paused {
            hotKeys.unregister()
            NativeSwitcher.restore()
            isPaused = true
        } else {
            isPaused = !takeOver()
        }
    }

    private func startTaps() {
        let taps = InputTaps(
            onCommandReleased: { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.controller.commandReleased() } }
            },
            onSessionKey: { [weak self] key in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.controller.sessionKey(key) } }
            }
        )
        self.taps = taps
        controller.attach(taps)
        if Permissions.accessibility, taps.start() { return }

        // Until Accessibility is granted, releases are caught by polling and the in-switcher keys do nothing.
        Permissions.requestAccessibility()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard Permissions.accessibility, let self, self.taps?.start() == true else { return }
                self.permissionPoll?.invalidate()
                self.permissionPoll = nil
                Diagnostics.log.notice("accessibility granted, input taps running")
            }
        }
    }

    private func previewApps() -> [Int32] {
        let own = ProcessInfo.processInfo.processIdentifier
        let snapshot = tracker.snapshot
        let withWindows = Set(snapshot.windows.map(\.pid))
        let exclusions = ExclusionMatcher(configStore.config.exclude)
        return snapshot.apps
            .filter { $0.pid != own && !exclusions.isExcluded(bundleId: $0.bundleId, hasWindows: withWindows.contains($0.pid)) }
            .map(\.pid)
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "InstantTab \(Bundle.main.shortVersion)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if !Permissions.accessibility {
            menu.addItem(item("Grant Accessibility…", #selector(openAccessibility), target: self))
        }
        if let error = configStore.error {
            menu.addItem(item("Config error: \(error)", #selector(openSettings), target: self))
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ",", target: self))
        let pause = item("Pause (use native Cmd+Tab)", #selector(togglePause), target: self)
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(item("Quit InstantTab", #selector(NSApplication.terminate(_:)), "q"))
    }

    /// Only visible while Settings is open, when InstantTab is a regular app.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        submenu("InstantTab", [
            item("About InstantTab", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(openSettings), ",", target: self),
            .separator(),
            item("Hide InstantTab", #selector(NSApplication.hide(_:)), "h"),
            item("Quit InstantTab", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return main
    }

    /// A nil target goes down the responder chain, which ends at NSApp.
    private func item(_ title: String, _ selector: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target
        return item
    }

    @objc private func openAccessibility() {
        Permissions.requestAccessibilityInSettings()
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func togglePause() {
        setPaused(!isPaused)
    }
}
