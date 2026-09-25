import AppKit
import AppSwitcherCore
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    private let displays = Displays()
    private let supervisor = ToolSupervisor()
    private var statusItem: NSStatusItem?
    private var signalSources: [DispatchSourceSignal] = []
    private lazy var settings = SettingsWindowController(
        makeModel: { [unowned self] in
            SettingsModel(configStore: configStore, actions: .init(
                toolState: { [unowned self] tool in supervisor.state(tool) },
                isEnabled: { tool in HostPreferences.isEnabled(tool) },
                setEnabled: { [unowned self] tool, enabled in setEnabled(tool, enabled) },
                retry: { [unowned self] tool in supervisor.retry(tool) },
                requestStatus: { [unowned self] in supervisor.requestStatus() },
                appSwitcher: { [unowned self] in supervisor.appSwitcherStatus },
                layoutSwitcher: { [unowned self] in supervisor.layoutSwitcherStatus },
                displays: { [unowned self] in displays.displays },
                mouseDisplay: { [unowned self] in displays.mouseDisplayId() },
                accessibilityGranted: { Permissions.accessibility },
                inputMonitoringGranted: { Permissions.inputMonitoring }
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
        LeftoverProcesses.stop()
        // One that had to be killed left native Cmd+Tab off. The Cmd+Tab tool turns it off again as it starts.
        NativeSwitcher.restore()
        displays.start()
        // Creates the Cmd+Tab config with defaults when missing, before the tool that reads it starts.
        configStore.start()
        LoginItem.repairIfMoved()
        NSApp.mainMenu = makeMainMenu()
        statusItem = makeStatusItem()

        supervisor.onChange = { [weak self] in self?.settings.refresh() }
        for tool in ToolId.allCases where HostPreferences.isEnabled(tool) {
            supervisor.start(tool)
        }
        if Handoff.consumeSettingsOpen() || chooseTools { settings.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        configStore.flush()
        supervisor.stopAllAndWait()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    /// Tools restore what they changed on their own way out, so the host only asks them to stop and waits.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            // Ignored first, so the default action does not kill the process before the source runs.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.configStore.flush()
                    if self.settings.isOpen { Handoff.markSettingsOpen() }
                    self.supervisor.stopAllAndWait()
                }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Instantools \(Bundle.main.shortVersion)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        for tool in ToolId.allCases {
            menu.addItem(toolItem(tool))
        }
        let running = { (tool: ToolId) in [.running, .starting].contains(self.supervisor.state(tool)) }
        if running(.appSwitcher), !Permissions.accessibility {
            menu.addItem(item("Grant Accessibility…", #selector(openAccessibility), target: self))
        }
        if running(.layoutSwitcher), !Permissions.accessibility, !Permissions.inputMonitoring {
            menu.addItem(item("Grant Input Monitoring…", #selector(openInputMonitoring), target: self))
        }
        if let error = configStore.error {
            menu.addItem(item("Config error: \(error)", #selector(openSettings), target: self))
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ",", target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit Instantools", #selector(NSApplication.terminate(_:)), "q"))
    }

    private func toolItem(_ tool: ToolId) -> NSMenuItem {
        let enabled = HostPreferences.isEnabled(tool)
        let title = switch supervisor.state(tool) {
        case .failed: "\(tool.name): Failed, click to retry"
        case .starting where enabled: "\(tool.name): Starting…"
        default: enabled ? tool.name : "\(tool.name): Paused"
        }
        let item = item(title, #selector(toggleTool(_:)), target: self)
        item.representedObject = tool.rawValue
        item.state = enabled && supervisor.state(tool) == .running ? .on : .off
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
