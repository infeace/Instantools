import AppKit
import AppSwitcherCore
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit
import WindowSnapperCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    /// Starts out as Rectangle's settings when Rectangle has any.
    private let snapStore = ConfigFileStore<SnapConfig>(initial: { SnapSystem.initialConfig() })
    private let displays = Displays()
    private let supervisor = ToolSupervisor()
    private let layouts = KeyboardLayoutWatcher()
    private let systemSettingsReturn = SystemSettingsReturn()
    private var statusItem: NSStatusItem?
    private lazy var settings = SettingsWindowController(
        makeModel: { [unowned self] in
            SettingsModel(configStore: configStore, snapStore: snapStore, actions: .init(
                toolState: { [unowned self] tool in supervisor.state(tool) },
                isEnabled: { tool in HostPreferences.isEnabled(tool) },
                setEnabled: { [unowned self] tool, enabled in setEnabled(tool, enabled) },
                retry: { [unowned self] tool in supervisor.retry(tool) },
                requestStatus: { [unowned self] in supervisor.requestStatus() },
                appSwitcher: { [unowned self] in supervisor.appSwitcherStatus },
                layoutSwitcher: { [unowned self] in supervisor.layoutSwitcherStatus },
                windowSnapper: { [unowned self] in supervisor.windowSnapperStatus },
                layouts: { [unowned self] in layouts.layouts },
                currentLayout: { [unowned self] in layouts.currentId },
                selectLayout: { [unowned self] id in layouts.select(id) },
                displays: { [unowned self] in displays.displays },
                mouseDisplay: { [unowned self] in displays.mouseDisplayId() },
                accessibilityGranted: { Permissions.accessibility },
                inputMonitoringGranted: { Permissions.inputMonitoring }
            ))
        }
    )

    private lazy var welcome = WelcomeWindowController(
        makeModel: { [unowned self] in
            WelcomeModel(actions: .init(
                isEnabled: { tool in HostPreferences.isEnabled(tool) },
                setEnabled: { [unowned self] tool, enabled in setEnabled(tool, enabled) },
                permissions: { PermissionState(accessibility: Permissions.accessibility, inputMonitoring: Permissions.inputMonitoring) },
                setStartAtLogin: { enabled in try LoginItem.setEnabled(enabled) },
                openSettings: { [unowned self] in settings.show() },
                snapConfig: { [unowned self] in snapStore.config }
            ))
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to a tool that just exited must fail the write, not end the host.
        signal(SIGPIPE, SIG_IGN)
        installSignalHandlers()
        Diagnostics.log.notice("launched \(Bundle.main.shortVersion, privacy: .public)")

        // Before the config store starts, since it would write defaults where the old config is copied to.
        let chooseTools = FirstLaunch.runIfNeeded()
        // Only when InstantTab may have left native Cmd+Tab off: after a host that crashed or was killed, or a
        // leftover InstantTab that may have had to be killed. Otherwise the setting may be another switcher's.
        supervisor.recoverNativeSwitcher(stoppedLeftoverSwitcher: LeftoverProcesses.stop())
        displays.start()
        // Creates missing config files, before the tools that read them start.
        configStore.start()
        snapStore.start()
        LoginItem.repairIfMoved()
        NSApp.mainMenu = makeMainMenu()
        statusItem = makeStatusItem()

        supervisor.onChange = { [weak self] in self?.settings.refresh() }
        layouts.onChange = { [weak self] in self?.settings.refresh() }
        layouts.start()
        systemSettingsReturn.onReturn = { [weak self] in
            guard let self else { return }
            // The one the user was in is in front of the other.
            let front = NSApp.orderedWindows.first { $0 === self.welcome.window || $0 === self.settings.window }
            if front == nil { return }
            if front === welcome.window { welcome.show() } else { settings.show() }
        }
        systemSettingsReturn.start()
        for tool in ToolId.allCases where HostPreferences.isEnabled(tool) {
            supervisor.start(tool)
        }
        if Handoff.consumeSettingsOpen() {
            settings.show()
        } else if chooseTools {
            welcome.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        configStore.flush()
        snapStore.flush()
        supervisor.stopAllAndWait()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if welcome.isOpen { welcome.show() } else { settings.show() }
        return false
    }

    /// Tools restore what they changed on their own way out, so the host asks them to stop and waits.
    private func installSignalHandlers() {
        TerminationSignals.handle { [weak self] in
            if let self {
                configStore.flush()
                snapStore.flush()
                if settings.isOpen { Handoff.markSettingsOpen() }
                supervisor.stopAllAndWait()
            }
            exit(0)
        }
    }

    private func setEnabled(_ tool: ToolId, _ enabled: Bool) {
        HostPreferences.setEnabled(tool, enabled)
        if enabled { supervisor.start(tool) } else { supervisor.stop(tool) }
        settings.refresh()
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    /// Built on open from what the host already holds, so it never waits on a tool.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Replies arrive after the menu is built, so they show the next time it opens.
        supervisor.requestStatus()
        let title = NSMenuItem(title: "Instantools \(Bundle.main.shortVersion)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        // It takes about 10 ms, so it is made at most once, and only when an answer depends on it.
        var inputMonitoringCheck: Bool?
        func inputMonitoring() -> Bool {
            if let inputMonitoringCheck { return inputMonitoringCheck }
            let granted = Permissions.inputMonitoring
            inputMonitoringCheck = granted
            return granted
        }
        for tool in ToolId.allCases {
            let enabled = HostPreferences.isEnabled(tool)
            let state = supervisor.state(tool)
            let active = ToolCondition.isActive(
                tool, state: state, handlesCmdTab: supervisor.appSwitcherStatus?.handlesCmdTab,
                tapRunning: supervisor.layoutSwitcherStatus?.tapRunning,
                snapAccessibility: supervisor.windowSnapperStatus?.accessibility, inputMonitoring: inputMonitoring
            )
            let row = toolItem(tool, condition: ToolCondition(enabled: enabled, state: state, isActive: active))
            row.state = enabled && state == .running ? .on : .off
            menu.addItem(row)
            switch tool {
            case .appSwitcher:
                if let samples = supervisor.appSwitcherStatus?.latencySamples, let typical = LatencyStats(chronological: samples).typical {
                    let speed = NSMenuItem(title: "Typical \(LatencyStats.milliseconds(typical))", action: nil, keyEquivalent: "")
                    speed.isEnabled = false
                    speed.indentationLevel = 1
                    menu.addItem(speed)
                }
            case .layoutSwitcher:
                guard enabled else { break }
                layouts.updateCurrent()
                for layout in layouts.layouts {
                    let choice = item(layout.name, #selector(selectLayout(_:)), target: self)
                    choice.image = layouts.menuIcon(for: layout.id)
                    choice.representedObject = layout.id
                    choice.state = layout.id == layouts.currentId ? .on : .off
                    choice.indentationLevel = 1
                    menu.addItem(choice)
                }
            case .windowSnapper:
                break
            }
        }

        var fixes: [NSMenuItem] = []
        let running = { (tool: ToolId) in [.running, .starting].contains(self.supervisor.state(tool)) }
        let accessibility = Permissions.accessibility
        if running(.appSwitcher) || running(.windowSnapper), !accessibility {
            fixes.append(item("Grant Accessibility…", #selector(openAccessibility), target: self))
        }
        // Cmd+Tab's taps need it too, but without Accessibility they are off anyway. InstantSnap needs only
        // Accessibility.
        if running(.layoutSwitcher) || (running(.appSwitcher) && accessibility), !inputMonitoring() {
            fixes.append(item("Grant Input Monitoring…", #selector(openInputMonitoring), target: self))
        }
        if let error = configStore.error {
            fixes.append(item("InstantTab config error: \(error)", #selector(openSettings), target: self))
        }
        if let error = snapStore.error {
            fixes.append(item("InstantSnap config error: \(error)", #selector(openSettings), target: self))
        }
        if !fixes.isEmpty {
            menu.addItem(.separator())
            fixes.forEach(menu.addItem)
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ",", target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit Instantools", #selector(NSApplication.terminate(_:)), "q"))
    }

    /// A suffix only when something is not as it should be.
    private func toolItem(_ tool: ToolId, condition: ToolCondition) -> NSMenuItem {
        let suffix: String? = switch condition {
        case .active: nil
        case .inactive: tool.inactiveStatus
        case .starting: "Starting…"
        case .off: "Off"
        case .failed: "Failed, click to retry"
        }
        let item = item(suffix.map { "\(tool.name): \($0)" } ?? tool.name, #selector(toggleTool(_:)), target: self)
        item.image = ToolIcons.menuImage(for: tool)
        item.representedObject = tool.rawValue
        return item
    }

    /// Only visible while Settings is open, when Instantools is a regular app.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        submenu("Instantools", [
            item("About Instantools", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(openSettings), ",", target: self),
            .separator(),
            item("Hide Instantools", #selector(NSApplication.hide(_:)), "h"),
            item("Quit Instantools", #selector(NSApplication.terminate(_:)), "q"),
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

    @objc private func toggleTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tool = ToolId(rawValue: raw) else { return }
        if case .failed = supervisor.state(tool) {
            HostPreferences.setEnabled(tool, true)
            supervisor.retry(tool)
            settings.refresh()
        } else {
            setEnabled(tool, !HostPreferences.isEnabled(tool))
        }
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        layouts.select(id)
    }

    @objc private func openAccessibility() {
        Permissions.requestAccessibilityInSettings()
    }

    @objc private func openInputMonitoring() {
        Permissions.requestInputMonitoringInSettings()
    }

    @objc private func openSettings() {
        settings.show()
    }
}
