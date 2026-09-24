import AppKit
import InstantTabCore
import SkyLightShim

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
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
    private var statusItem: NSStatusItem?
    private var isPaused = false
    private var passThrough = BundleIdMatcher([])
    private lazy var settings = SettingsWindowController(
        makeModel: { [unowned self] in
            SettingsModel(configStore: configStore, actions: .init(
                isPaused: { [unowned self] in isPaused },
                setPaused: { [unowned self] paused in setPaused(paused) },
                latency: { [unowned self] in controller.latency },
                displays: { [unowned self] in displays.displays },
                mouseDisplay: { [unowned self] in displays.mouseDisplayId() },
                focusedDisplay: { [unowned self] in
                    DisplayScope.focusedDisplay(
                        in: tracker.snapshot, frontmostPid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                        displays: displays.displays
                    )
                },
                accessibilityGranted: { Permissions.accessibility },
                recentApps: { [unowned self] in controller.previewEntries() }
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
        // Raises run on their own queue, but a hung app would otherwise pin a thread for the 6s default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        Diagnostics.log.notice("launched \(Bundle.main.shortVersion, privacy: .public), SkyLight focus available: \(SkyLight.canFocusWindows)")

        displays.start()
        displays.onChange = { [weak self] in
            self?.controller.resolveGroups()
            self?.tracker.refreshWindows()
        }
        hotKeys.onPress = { [weak self] action, eventNanoseconds in
            self?.controller.hotKeyPressed(action, eventNanoseconds: eventNanoseconds)
        }
        // Before the config loads, so a pass-through app already in front gets its Cmd+Tab back.
        isPaused = !takeOver()
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
    /// without one. If it cannot go off, it would win over the hotkeys, so InstantTab reports Paused.
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

    private func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        if paused {
            hotKeys.unregister()
            NativeSwitcher.restore()
            isPaused = true
        } else {
            isPaused = !takeOver()
            applyPassThrough()
        }
    }

    /// While a pass-through app is in front, the hotkeys are let go with native Cmd+Tab still off, so the key
    /// reaches that app. Registering and unregistering do nothing when already done.
    private func applyPassThrough(front: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        guard !isPaused else { return }
        if passThrough.matches(front?.bundleIdentifier) {
            hotKeys.unregister()
        } else if !hotKeys.register() {
            // Without the hotkeys and with native Cmd+Tab off, the Mac would have no switcher at all.
            NativeSwitcher.restore()
            isPaused = true
            Diagnostics.log.error("could not take Cmd+Tab back from a pass-through app, native switcher restored")
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
        submenu("View", [
            // The split view handles it, so a sidebar dragged closed can always come back.
            item("Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", modifiers: [.command, .control]),
        ])
        submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return main
    }

    private func item(
        _ title: String, _ selector: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
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

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
