import InstantTabCore
import SwiftUI

struct GeneralPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            status
            switcher
            startup
            configFile
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private var status: some View {
        Section("Status") {
            Toggle(isOn: model.enabled) {
                Text("Use InstantTab for Cmd+Tab")
                Text(model.isPaused ? "Paused: Cmd+Tab opens the macOS switcher." : "Cmd+Tab opens InstantTab.")
            }
            LabeledContent {
                if model.accessibilityGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant Access…") { model.grantAccessibility() }
                }
            } label: {
                Text("Accessibility")
                Text("Needed for Esc, the arrow keys and raising the right window of an app.")
            }
            LabeledContent {
                Text(drawTime)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text("Draw time")
                Text("Key press to the switcher on screen, after the show delay. One frame on \(model.displayName) is \(String(format: "%.1f", model.frameMilliseconds))ms, the fastest a screen can show it.")
            }
        }
    }

    private var switcher: some View {
        Section("Switcher") {
            LabeledContent {
                ValueSlider(value: showDelay, range: 0...500, step: 10, unit: "ms")
            } label: {
                Text("Show delay")
                Text("A Cmd+Tab released sooner switches without drawing the switcher.")
            }
            LabeledContent {
                ValueSlider(value: model.binding(\.iconSize), range: 32...256, step: 8, unit: "pt")
            } label: {
                Text("Icon size")
                Text("Icons shrink automatically when the apps do not fit.")
            }
            Picker(selection: model.binding(\.scope)) {
                Text("All monitors").tag(Config.Scope.all)
                Text("Monitor under the mouse").tag(Config.Scope.mouseDisplay)
            } label: {
                Text("Show apps from")
                Text("Monitor groups come with the Monitors settings.")
            }
            Picker(selection: model.binding(\.windowlessApps)) {
                Text("Show in recent order").tag(Config.Placement.show)
                Text("Show at the end").tag(Config.Placement.end)
                Text("Hide").tag(Config.Placement.hide)
            } label: {
                Text("Apps without visible windows")
                Text("Hidden, minimized, or with no window open.")
            }
        }
    }

    private var startup: some View {
        Section("Startup") {
            Toggle(isOn: model.startAtLogin) {
                Text("Start at login")
                Text("Also relaunches InstantTab if it ever crashes, so Cmd+Tab keeps working.")
            }
            if model.loginNeedsApproval {
                LabeledContent {
                    Button("Open Login Items") { model.openLoginItemsSettings() }
                } label: {
                    Label("Waiting for your approval in Login Items", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            if let error = model.loginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var configFile: some View {
        Section {
            LabeledContent("Location") {
                Text(verbatim: "~/.config/instanttab/config.json5")
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            if let error = model.configStore.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            ForEach(model.configStore.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Config file")
        } footer: {
            HStack {
                Text("Edits made here and in the file stay in sync.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") { model.revealConfigFile() }
                Button("Open in Editor") { model.openConfigFile() }
            }
        }
    }

    private var showDelay: Binding<Double> {
        let delay = model.binding(\.showDelayMs)
        return Binding(get: { Double(delay.wrappedValue) }, set: { delay.wrappedValue = Int($0) })
    }

    private var drawTime: String {
        guard let typical = model.latency.percentile(50), let slow = model.latency.percentile(95) else {
            return "No switches measured yet"
        }
        return "\(LatencyStats.milliseconds(typical)) typical, 95% under \(LatencyStats.milliseconds(slow))"
    }
}
