import InstantTabCore
import SwiftUI

struct GeneralPane: View {
    let model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        PaneScroll { compact in
            PaneHeader(pane: .general, subtitle: "How InstantTab takes over Cmd+Tab and how the switcher looks.")
            hero(compact: compact)
            if !model.accessibilityGranted { permissionCard(compact: compact) }
            speed(compact: compact)
            switcher
            startup
            configuration
        }
        .navigationTitle("General")
    }

    // MARK: Sections

    /// The live preview, with the main switch on a glass bar floating over it.
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
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Card.stroke))
    }

    private func statusBar(compact: Bool) -> some View {
        HStack(spacing: 12) {
            StatusDot(color: model.isPaused ? .orange : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isPaused ? "Paused" : "InstantTab handles Cmd+Tab")
                    .font(.headline)
                    .lineLimit(1)
                if !compact {
                    Text(model.isPaused ? "Cmd+Tab opens the macOS switcher for now." : "Hold Cmd and press Tab. Release to switch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle("Use InstantTab for Cmd+Tab", isOn: model.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassPanel(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func permissionCard(compact: Bool) -> some View {
        let text = VStack(alignment: .leading, spacing: 2) {
            Text("Allow Accessibility access")
                .font(.headline)
            Text("Cmd+Tab already works. With access, Esc cancels, the arrow keys move, and the right window of an app comes forward.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        let button = Button("Allow…") { model.grantAccessibility() }
            .glassButton(prominent: true)
            .controlSize(.large)
        return HStack(alignment: compact ? .top : .center, spacing: 14) {
            IconTile(symbol: "hand.raised.fill", colors: [.orange, Color(red: 0.93, green: 0.42, blue: 0.1)], size: 34)
            if compact {
                VStack(alignment: .leading, spacing: 10) { text; button }
            } else {
                text
                Spacer(minLength: 12)
                button
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: Card.shape)
        .overlay(Card.shape.strokeBorder(Color.orange.opacity(0.3)))
    }

    private func speed(compact: Bool) -> some View {
        SettingsCard(
            title: "Speed",
            footer: "Time from pressing Tab to the switcher on screen, after the show delay. One frame on \(model.displayName) is \(String(format: "%.1f", model.frameMilliseconds))ms, the fastest any app can appear."
        ) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 12) {
                        speedStat
                        speedChart.frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        speedStat
                        Spacer(minLength: 8)
                        speedChart.frame(width: 220)
                    }
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
                Text(slowestText)
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

    @ViewBuilder private var speedChart: some View {
        if model.latency.count > 0 {
            LatencyBars(samples: model.latency.chronological, frameMilliseconds: model.frameMilliseconds)
                .frame(height: 46)
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
            if model.loginNeedsApproval {
                RowDivider()
                SettingsRow(title: "Waiting for your approval", subtitle: "macOS asks you to allow InstantTab in Login Items.") {
                    Button("Open Login Items") { model.openLoginItemsSettings() }
                        .glassButton()
                }
            }
            if let error = model.loginError {
                RowDivider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var configuration: some View {
        SettingsCard(title: "Configuration") {
            SettingsRow(title: "Settings file", subtitle: "~/.config/instanttab/config.json5, kept in sync with this window.") {
                HStack(spacing: 8) {
                    Button("Show in Finder") { model.revealConfigFile() }
                    Button("Open") { model.openConfigFile() }
                }
                .glassButton()
            }
            if let error = model.configStore.error {
                RowDivider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(model.configStore.warnings, id: \.self) { warning in
                RowDivider()
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Helpers

    private var showDelay: Binding<Double> {
        let delay = model.binding(\.showDelayMs)
        return Binding(get: { Double(delay.wrappedValue) }, set: { delay.wrappedValue = Int($0) })
    }

    private var slowestText: String {
        guard let slow = model.latency.percentile(95) else { return "" }
        return "Typical. 95% of \(model.latency.count) switches under \(LatencyStats.milliseconds(slow))."
    }

    private func verdict(for nanoseconds: UInt64) -> some View {
        let frames = Double(nanoseconds) / 1_000_000 / model.frameMilliseconds
        let (text, color): (String, Color) = frames <= 1 ? ("Within 1 frame", .green)
            : frames <= 2 ? ("Within 2 frames", .yellow) : ("Slower than 2 frames", .orange)
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
