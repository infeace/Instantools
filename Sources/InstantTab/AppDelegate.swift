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
        tracker.onChange = { [weak self] in
            guard let self else { return }
            icons.sync(with: tracker.snapshot.apps.map(\.pid))
            controller.modelChanged()
        }
        displays.onChange = { [weak self] in self?.tracker.refreshWindows() }
        tracker.start()
        icons.sync(with: tracker.snapshot.apps.map(\.pid))

        hotKeys.onPress = { [weak self] action, eventNanoseconds in
            self?.controller.hotKeyPressed(action, eventNanoseconds: eventNanoseconds)
        }
        activate()
        startTaps()
        controller.warmUp()
        statusItem = makeStatusItem()
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
        menu.addItem(disabled("Draw time: \(controller.latency.summary)"))
        if !Permissions.accessibility {
            menu.addItem(action("Grant Accessibility…", #selector(openAccessibility)))
        }
        if let error = configStore.error {
            menu.addItem(disabled("Config error: \(error)"))
        } else if !configStore.warnings.isEmpty {
            menu.addItem(disabled("Config: \(configStore.warnings.joined(separator: "; "))"))
        }
        menu.addItem(.separator())
        menu.addItem(action("Open Config File", #selector(openConfig)))
        menu.addItem(action("Reload Config", #selector(reloadConfig)))
        menu.addItem(.separator())
        let login = action(LoginItem.needsApproval ? "Start at Login (approve in Settings)" : "Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let pause = action("Pause (use native Cmd+Tab)", #selector(togglePause))
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(action("Quit InstantTab", #selector(NSApplication.terminate(_:)), key: "q"))
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

    @objc private func openConfig() {
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    @objc private func reloadConfig() {
        configStore.load()
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
            if LoginItem.needsApproval { LoginItem.openSettings() }
        } catch {
            Diagnostics.log.error("login item: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change Start at Login"
            alert.runModal()
        }
    }

    @objc private func togglePause() {
        isPaused.toggle()
        isPaused ? deactivate() : activate()
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
