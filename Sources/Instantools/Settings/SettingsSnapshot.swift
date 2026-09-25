import AppKit
import AppSwitcherCore
import AppSwitcherKit
import InstantoolsCore
import SkyLightShim
import SwiftUI

/// Renders a Settings pane to a PNG and exits. It starts no tool, runs no migration, writes no config and
/// never touches Cmd+Tab. Capturing its own window needs no Screen Recording permission.
@MainActor
enum SettingsSnapshot {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot-settings") else { return }
        let paneName = arguments.count > flag + 1 ? arguments[flag + 1] : ""
        guard arguments.count > flag + 2, paneName == "group-editor" || SettingsPane(rawValue: paneName) != nil else {
            let panes = (SettingsPane.allCases.map(\.rawValue) + ["group-editor"]).joined(separator: "|")
            FileHandle.standardError.write(Data("usage: Instantools --snapshot-settings <\(panes)> <out.png> [light|dark] [--sample] [--narrow] [--no-access]\n".utf8))
            exit(2)
        }
        let output = URL(fileURLWithPath: arguments[flag + 2])
        let dark = arguments.count > flag + 3 && arguments[flag + 3] == "dark"
        let sample = arguments.contains("--sample")
        let access = !arguments.contains("--no-access")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let displays = Displays()
        displays.start()
        let store = ConfigStore(persists: false)
        store.load()
        if sample {
            store.update {
                $0.exclude = [
                    .init(bundleId: "com.apple.finder", when: .noWindows),
                    .init(bundleId: "com.apple.Safari"),
                    .init(bundleId: "com.parallels.*"),
                    .init(bundleId: "com.example.Missing"),
                ]
                $0.displayGroups = [
                    DisplayGroup(name: "Laptop", rules: [.builtIn]),
                    DisplayGroup(name: "Desk", rules: [.external, .name("DELL*")]),
                ]
                $0.scope = .mouseGroup
                $0.bindAppKey("f", to: "com.apple.finder")
                $0.bindAppKey("s", to: "com.apple.Safari")
                $0.bindAppKey("1", to: "com.example.Missing")
                $0.passThrough = ["com.parallels.desktop.console", "com.apple.ScreenSharing"]
            }
        }
        // With --sample both tools run, and the fourth app has no visible window, to show it dimmed.
        let switcher = AppSwitcherStatus(
            latencySamples: [6_100_000, 7_400_000, 6_800_000, 8_200_000, 7_000_000, 9_000_000, 6_400_000],
            focusedDisplay: displays.mouseDisplayId(),
            recentApps: NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0 != .current }
                .enumerated()
                .map { index, app in
                    AppSwitcherStatus.RecentApp(pid: app.processIdentifier, name: app.localizedName ?? "App", hasWindow: index != 3)
                },
            tapsRunning: access,
            handlesCmdTab: true
        )
        let layout = LayoutSwitcherStatus(tapRunning: true, layouts: ["ABC", "Bulgarian - Phonetic"])
        let model = SettingsModel(configStore: store, actions: .init(
            toolState: { _ in sample ? .running : .off },
            isEnabled: { _ in sample },
            setEnabled: { _, _ in },
            retry: { _ in },
            requestStatus: {},
            appSwitcher: { sample ? switcher : nil },
            layoutSwitcher: { sample ? layout : nil },
            displays: { displays.displays },
            mouseDisplay: { displays.mouseDisplayId() },
            accessibilityGranted: { access },
            inputMonitoringGranted: { access }
        ))
        let view: NSView = if let pane = SettingsPane(rawValue: paneName) {
            NSHostingView(rootView: SettingsView(model: model, initialPane: pane))
        } else {
            NSHostingView(rootView: GroupEditor(
                draft: GroupDraft(group: DisplayGroup(name: "Desk", rules: [.external, .name("DELL*")]), originalName: "Desk"),
                displays: displays.displays, takenNames: ["Laptop"], canSave: true, save: { _ in }
            ))
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: arguments.contains("--narrow") ? 720 : 900, height: 1500),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = view
        // Drawn normally but behind the desktop picture, so nothing flashes on screen.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.ignoresMouseEvents = true
        window.center()
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        guard let image = SkyLight.captureOwnWindow(CGWindowID(window.windowNumber)),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? png.write(to: output)) != nil
        else { exit(1) }
        exit(0)
    }
}
