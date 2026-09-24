import AppKit
import InstantTabCore
import SkyLightShim
import SwiftUI

/// `InstantTab --snapshot-settings <pane> <out.png> [light|dark]` renders a Settings pane to a PNG and
/// exits, without touching Cmd+Tab. It lets UI changes be checked without Screen Recording permission.
@MainActor
enum SettingsSnapshot {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot-settings"), arguments.count > flag + 2 else { return }
        let paneName = arguments[flag + 1]
        let pane = SettingsPane(rawValue: paneName) ?? .general
        let output = URL(fileURLWithPath: arguments[flag + 2])
        let dark = arguments.count > flag + 3 && arguments[flag + 3] == "dark"

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let displays = Displays()
        displays.start()
        let store = ConfigStore(persists: false)
        store.load()
        if arguments.contains("--sample") {
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
            }
        }
        let model = SettingsModel(configStore: store, actions: .init(
            isPaused: { false },
            setPaused: { _ in },
            latency: {
                var stats = LatencyStats()
                for sample: UInt64 in [6_100_000, 7_400_000, 8_200_000, 9_000_000, 12_600_000] { stats.record(sample) }
                return stats
            },
            displays: { displays.displays },
            mouseDisplay: { displays.mouseDisplayId() }
        ))
        let view: NSView = if paneName == "group-editor" {
            NSHostingView(rootView: GroupEditor(
                draft: GroupDraft(group: DisplayGroup(name: "Desk", rules: [.external, .name("DELL*")]), originalName: "Desk"),
                displays: displays.displays, takenNames: ["Laptop"], save: { _ in }
            ))
        } else {
            NSHostingView(rootView: SettingsView(model: model, initialPane: pane))
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 1000),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.contentView = view
        // Drawn normally but kept behind the desktop picture, so nothing flashes on screen.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.ignoresMouseEvents = true
        window.center()
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        guard let image = SkyLight.captureOwnWindow(CGWindowID(window.windowNumber)),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { exit(1) }
        do {
            try png.write(to: output)
            exit(0)
        } catch {
            exit(1)
        }
    }
}
