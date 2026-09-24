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
                recentApps: { [unowned self] in
                    let own = ProcessInfo.processInfo.processIdentifier
                    return tracker.snapshot.apps.map(\.pid).filter { $0 != own }
                }
            ))
        },
        onOpenChange: { [unowned self] _ in tracker.reload() }
    )
    /// Keeps App Nap from coalescing the show delay and release timers.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "Cmd+Tab must respond instantly"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeSwitcher.installExitHandlers()
        // A hung app must never hold up focusing: every Accessibility call in this process gives up after 0.5s.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        Diagnostics.log.notice("launched \(Self.version, privacy: .public), SkyLight focus available: \(SkyLight.canFocusWindows)")

        configStore.onChange = { [weak self] config in self?.controller.config = config }
        configStore.start()
        controller.config = configStore.config

        displays.start()
        controller.resolveGroups()
        tracker.onChange = { [weak self] in
            guard let self else { return }
            icons.sync(with: tracker.snapshot.apps.map(\.pid))
            controller.modelChanged()
        }
        displays.onChange = { [weak self] in
            self?.controller.resolveGroups()
            self?.tracker.refreshWindows()
        }
        tracker.start()
        icons.sync(with: tracker.snapshot.apps.map(\.pid))

        hotKeys.onPress = { [weak self] action, eventNanoseconds in
            self?.controller.hotKeyPressed(action, eventNanoseconds: eventNanoseconds)
        }
        activate()
        startTaps()
        controller.warmUp()
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

    /// Reopening the app from Finder or Spotlight opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    // MARK: Takeover

    /// Takes over Cmd+Tab only once the hotkeys are registered, so a failure never leaves the Mac without one.
    private func activate() {
        if hotKeys.register() {
            NativeSwitcher.disable()
        } else {
            NativeSwitcher.restore()
            Diagnostics.log.error("could not register Cmd+Tab, native switcher left on")
        }
    }

    private func deactivate() {
        hotKeys.unregister()
        NativeSwitcher.restore()
    }

    private func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        paused ? deactivate() : activate()
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

        // Until Accessibility is granted, releases are caught by polling and Esc/arrows are unavailable.
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

    // MARK: Menu

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "InstantTab")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabled("InstantTab \(Self.version)"))
        if !Permissions.accessibility {
            menu.addItem(action("Grant Accessibility…", #selector(openAccessibility)))
        }
        if let error = configStore.error {
            menu.addItem(action("Config error: \(error)", #selector(openSettings)))
        }
        menu.addItem(.separator())
        menu.addItem(action("Settings…", #selector(openSettings), key: ","))
        let pause = action("Pause (use native Cmd+Tab)", #selector(togglePause))
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(action("Quit InstantTab", #selector(NSApplication.terminate(_:)), key: "q"))
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
        func item(_ title: String, _ selector: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = target
            return item
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

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = selector == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    @objc private func openAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func togglePause() {
        setPaused(!isPaused)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
