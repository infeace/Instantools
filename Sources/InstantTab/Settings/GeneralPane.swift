import InstantTabCore
import SwiftUI

struct GeneralPane: View {
    let model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        PaneScroll { compact in
            PaneHeader(pane: .general, subtitle: "How InstantTab takes over Cmd+Tab and how the switcher looks.")
            FileProblemBanner(configStore: model.configStore)
            hero(compact: compact)
            if !model.accessibilityGranted {
                Callout(
                    symbol: "hand.raised.fill",
                    colors: [.orange, Color(red: 0.93, green: 0.42, blue: 0.1)],
                    title: "Allow Accessibility access",
                    message: "Cmd+Tab already works. With access, Esc, the arrow keys, Q and H work in the switcher, and the right window of an app comes forward.",
                    action: "Allow…",
                    perform: model.grantAccessibility
                )
            }
            speed(compact: compact)
            Group {
                switcher
                startup
            }
            .disabled(model.configStore.fileIsBroken)
            configuration
        }
        .navigationTitle("General")
    }

    private func hero(compact: Bool) -> some View {
        SwitcherPreview(
            apps: model.previewApps,
            iconSize: model.configStore.config.iconSize,
            isActive: !model.isPaused,
            bottomInset: 72
        )
        .frame(height: 260)
        .overlay(alignment: .bottom) {
            statusBar(compact: compact).padding(12)
        }
        .overlay(Hero.shape.strokeBorder(Card.stroke))
    }

    private func statusBar(compact: Bool) -> some View {
        StatusBar(
            title: model.isPaused ? "Paused" : "InstantTab handles Cmd+Tab",
            subtitle: compact ? nil : model.isPaused ? "Cmd+Tab opens the macOS switcher for now." : "Hold Cmd and press Tab. Release to switch."
        ) {
            StatusDot(color: model.isPaused ? .orange : .green)
        } trailing: {
            Toggle("Use InstantTab for Cmd+Tab", isOn: model.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func speed(compact: Bool) -> some View {
        let layout = adaptiveLayout(compact: compact, spacing: 18)
        return SettingsCard(
            title: "Speed",
            footer: "Time from pressing Tab to the switcher on screen, after the show delay. One frame on \(model.displayName) is \(String(format: "%.1f", model.frameMilliseconds))ms, the fastest any app can appear."
        ) {
            layout {
                speedStat
                if !compact { Spacer(minLength: 8) }
                if model.latency.count > 0 {
                    LatencyBars(samples: model.latency.chronological, frameMilliseconds: model.frameMilliseconds)
                        .frame(height: 46)
                        .frame(maxWidth: compact ? .infinity : 220)
                }
            }
            .padding(16)
        }
    }

    private var speedStat: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let typical = model.latency.percentile(50) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LatencyStats.milliseconds(typical))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    verdict(for: typical)
                }
                Text(spreadText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not measured yet")
                    .font(.title3.weight(.semibold))
                Text("Hold Cmd+Tab a few times to see how fast the switcher appears.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var switcher: some View {
        SettingsCard(title: "Switcher") {
            SettingsRow(title: "Show delay", subtitle: "A Cmd+Tab released sooner switches without drawing anything, like native.") {
                ValueSlider(value: showDelay, range: 0...500, step: 10, unit: "ms")
            }
            RowDivider()
            SettingsRow(title: "Icon size", subtitle: "Icons shrink on their own when many apps are open.") {
                ValueSlider(value: model.binding(\.iconSize), range: 32...256, step: 8, unit: "pt")
            }
            RowDivider()
            SettingsRow(title: "Apps without visible windows", subtitle: "Hidden, minimized, or with no window open.") {
                Picker("Apps without visible windows", selection: model.binding(\.windowlessApps)) {
                    Text("In order").tag(Config.Placement.show)
                    Text("At the end").tag(Config.Placement.end)
                    Text("Hidden").tag(Config.Placement.hide)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var startup: some View {
        SettingsCard(title: "Startup") {
            SettingsRow(title: "Start at login", subtitle: "Takes effect at your next login. InstantTab then also comes back by itself if it ever crashes.") {
                Toggle("Start at login", isOn: model.startAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if model.loginBlocked {
                RowDivider()
                SettingsRow(title: "Turned off in Login Items", subtitle: "macOS will not start InstantTab until you allow it again.") {
                    Button("Open Login Items") { LoginItem.openLoginItemsSettings() }
                        .glassButton()
                }
            }
            if let error = model.loginError {
                RowDivider()
                MessageRow(text: error)
            }
        }
    }

    private var configuration: some View {
        SettingsCard(title: "Configuration") {
            SettingsRow(title: "Settings file", subtitle: "~/.config/instanttab/config.json5, kept in sync with this window.") {
                HStack(spacing: 8) {
                    Button("Show in Finder") { model.configStore.revealInFinder() }
                    Button("Open") { model.configStore.openInEditor() }
                }
                .glassButton()
            }
            if let error = model.configStore.error, !model.configStore.fileIsBroken {
                RowDivider()
                MessageRow(text: error)
            }
            ForEach(model.configStore.warnings, id: \.self) { warning in
                RowDivider()
                MessageRow(text: warning, isError: false)
            }
            RowDivider()
            SettingsRow(title: "Reset all settings", subtitle: "Back to defaults, including excluded apps and monitor groups.") {
                Button("Reset…", role: .destructive) { confirmingReset = true }
                    .glassButton()
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset All Settings", role: .destructive) { model.resetAll() }
        } message: {
            Text("Excluded apps and monitor groups are removed too. This cannot be undone.")
        }
    }

    private var showDelay: Binding<Double> {
        let delay = model.binding(\.showDelayMs)
        return Binding(get: { Double(delay.wrappedValue) }, set: { delay.wrappedValue = Int($0) })
    }

    /// With few samples the 95th percentile is just the slowest one, so it is called that.
    private var spreadText: String {
        let count = model.latency.count
        guard let slow = model.latency.percentile(95) else { return "" }
        let switches = count == 1 ? "1 switch" : "\(count) switches"
        return count < 20
            ? "Typical. Slowest of \(switches): \(LatencyStats.milliseconds(slow))."
            : "Typical. 95% of \(switches) under \(LatencyStats.milliseconds(slow))."
    }

    private func verdict(for nanoseconds: UInt64) -> some View {
        let frames = Double(nanoseconds) / 1_000_000 / model.frameMilliseconds
        let (text, color): (String, Color) = frames <= 1 ? ("Within 1 frame", .green)
            : frames <= 2 ? ("Within 2 frames", .orange) : ("Slower than 2 frames", .red)
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
