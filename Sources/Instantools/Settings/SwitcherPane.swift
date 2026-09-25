import AppSwitcherCore
import AppSwitcherKit
import SwiftUI

struct SwitcherPane: View {
    let model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        let status = status
        PaneScroll { _ in
            PaneHeader(pane: .switcher, subtitle: "How Instantools takes over Cmd+Tab and how the switcher looks.")
            FileProblemBanner(configStore: model.configStore)
            Hero {
                SwitcherPreview(
                    apps: model.previewApps, iconSize: model.configStore.config.iconSize,
                    badge: model.isActive(.appSwitcher) ? nil : status.title, appKeys: model.configStore.config.appKeys
                )
            } bar: {
                ToolStatusBar(model: model, tool: .appSwitcher, status: status, toggleLabel: "Use Instantools for Cmd+Tab")
            }
            if model.isEnabled(.appSwitcher), !model.accessibilityGranted {
                Callout(
                    permission: .accessibility,
                    title: "Allow Accessibility access",
                    message: model.isActive(.appSwitcher)
                        ? "Cmd+Tab already works. With access, the keys inside the switcher work too, and the right window of an app comes forward."
                        : "With access, the keys inside the switcher work, and the right window of an app comes forward."
                )
            }
            if model.isEnabled(.appSwitcher), model.inputMonitoringSwitchedOff {
                Callout(
                    permission: .inputMonitoring,
                    title: "Input Monitoring is switched off",
                    message: "The keys inside the switcher do nothing until it is back on for Instantools."
                )
            }
            SpeedCard(model: model)
            switcher
                .disabled(model.configStore.fileIsBroken)
            configuration
        }
    }

    private var status: (title: String, subtitle: String, color: Color) {
        guard model.isEnabled(.appSwitcher) else {
            return ("Off", "Cmd+Tab opens the macOS switcher for now.", .orange)
        }
        switch model.state(of: .appSwitcher) {
        case .failed(let reason):
            return ("Cmd+Tab stopped", "\(reason) The macOS switcher is back until you try again.", .red)
        case .running where model.handlesCmdTab == false:
            return ("macOS kept Cmd+Tab", "Its own switcher could not be turned off. Turn this off and on to try again.", .orange)
        case .running:
            return ("Instantools handles Cmd+Tab", "Hold Cmd and press Tab. Release to switch.", .green)
        case .starting, .off:
            return ("Starting", "Cmd+Tab opens the macOS switcher until it is ready.", .orange)
        }
    }

    private var switcher: some View {
        SettingsCard(title: "Switcher") {
            SettingsRow(title: "Show delay", subtitle: "A Cmd+Tab released sooner switches without drawing anything, like native.") {
                ValueSlider(label: "Show delay", value: showDelay, range: 0...500, step: 10, unit: "ms")
            }
            RowDivider()
            SettingsRow(title: "Icon size", subtitle: "Icons shrink on their own when many apps are open.") {
                ValueSlider(label: "Icon size", value: model.binding(\.iconSize), range: 32...256, step: 8, unit: "pt")
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

    private var configuration: some View {
        SettingsCard(title: "Configuration") {
            SettingsRow(title: "Settings file", subtitle: "\(ConfigStore.fileURL.abbreviatedPath), kept in sync with this window.") {
                HStack(spacing: 8) {
                    Button("Show in Finder") { model.configStore.revealInFinder() }
                    Button("Open") { model.configStore.openInEditor() }
                }
                .glassButton()
            }
            ForEach(Array(model.configStore.warnings.enumerated()), id: \.offset) { _, warning in
                RowDivider()
                MessageRow(text: warning, isError: false)
            }
            RowDivider()
            SettingsRow(
                title: "Reset Cmd+Tab settings",
                subtitle: "Back to defaults, including app keys, excluded apps, apps that keep Cmd+Tab and monitor groups."
            ) {
                Button("Reset…", role: .destructive) { confirmingReset = true }
                    .glassButton()
            }
        }
        .confirmationDialog("Reset Cmd+Tab settings?", isPresented: $confirmingReset) {
            Button("Reset Cmd+Tab Settings", role: .destructive) { model.configStore.resetToDefaults() }
        } message: {
            Text("App keys, excluded apps, apps that keep Cmd+Tab and monitor groups are removed too. This cannot be undone.")
        }
    }

    private var showDelay: Binding<Double> {
        let delay = model.binding(\.showDelayMs)
        return Binding(get: { Double(delay.wrappedValue) }, set: { delay.wrappedValue = Int($0) })
    }
}

/// Its own view, so a dragged slider does not re-sort the latency samples on every tick.
private struct SpeedCard: View {
    let model: SettingsModel
    @Environment(\.compactLayout) private var compact

    var body: some View {
        let latency = model.latency
        let typical = latency.percentile(50)
        let slow = latency.percentile(95)
        let layout = adaptiveLayout(compact: compact, spacing: 18)
        SettingsCard(
            title: "Speed",
            footer: "Time from pressing Tab to the switcher on screen, after the show delay. One frame on \(model.displayName) is \(String(format: "%.1f", model.frameMilliseconds))ms, the fastest any app can appear."
        ) {
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    if let typical, let slow {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(LatencyStats.milliseconds(typical))
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            verdict(for: typical)
                        }
                        Text(spreadText(count: latency.count, slow: slow))
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
                if !compact { Spacer(minLength: 8) }
                if latency.count > 0 {
                    LatencyBars(samples: latency.chronological, frameMilliseconds: model.frameMilliseconds)
                        .frame(height: 46)
                        .frame(maxWidth: compact ? .infinity : 220)
                }
            }
            .padding(Card.inset)
        }
    }

    /// With few samples the 95th percentile is just the slowest one, so it is called that.
    private func spreadText(count: Int, slow: UInt64) -> String {
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
