import InstantoolsCore
import InstantoolsKit
import SwiftUI

struct LanguagePane: View {
    let model: SettingsModel

    var body: some View {
        PaneScroll { compact in
            PaneHeader(pane: .language, subtitle: "Switch the keyboard layout with Control+Command, pressed in either order.")
            Hero {
                ChordPicture(layouts: model.layouts, isActive: isActive)
            } bar: {
                statusBar(compact: compact)
            }
            if model.needsInputMonitoring {
                Callout(
                    symbol: "keyboard.fill",
                    colors: SettingsPane.language.colors,
                    title: "Allow Input Monitoring",
                    message: "Language needs it to see Control and Command. Allowing Accessibility for Cmd+Tab covers it too.",
                    action: "Allow…",
                    perform: Permissions.requestInputMonitoringInSettings
                )
            }
            howItWorks
        }
    }

    private var isActive: Bool {
        model.state(of: .layoutSwitcher) == .running && model.layoutTapRunning != false
    }

    private func statusBar(compact: Bool) -> some View {
        let status = status
        return StatusBar(title: status.title, subtitle: compact ? nil : status.subtitle) {
            StatusDot(color: status.color)
        } trailing: {
            HStack(spacing: 10) {
                if case .failed = model.state(of: .layoutSwitcher) {
                    Button("Try Again") { model.retry(.layoutSwitcher) }
                        .glassButton()
                }
                Toggle("Use Control+Command to switch layouts", isOn: model.enabled(.layoutSwitcher))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var status: (title: String, subtitle: String, color: Color) {
        guard model.isEnabled(.layoutSwitcher) else {
            return ("Off", "Control+Command does nothing for now.", .orange)
        }
        switch model.state(of: .layoutSwitcher) {
        case .failed(let reason):
            return ("Language stopped", reason, .red)
        case .running where model.layoutTapRunning == false:
            return ("Waiting for permission", "Allow Input Monitoring or Accessibility to start.", .orange)
        case .running where model.layoutTapRunning != nil && model.layouts.count < 2:
            return ("Only one layout", "Add another in System Settings > Keyboard > Text Input.", .orange)
        case .running:
            return ("Control+Command switches the layout", "Press both, in either order, to go back to the last layout.", .green)
        case .starting, .off:
            return ("Starting", "Control+Command switches layouts once it is ready.", .orange)
        }
    }

    private var howItWorks: some View {
        SettingsCard(title: "How it works", footer: "Emoji & Symbols and Dictation are skipped. Left and right keys count the same.") {
            fact("bolt.fill", "Switches the moment both keys are down", "Control then Command, Command then Control, or both at once.")
            RowDivider(indented: true)
            fact("keyboard", "Typing never cancels it", "Keys typed while the chord is still down never undo the switch, so it sticks in the middle of fast typing.")
            RowDivider(indented: true)
            fact("command", "Ctrl+Cmd shortcuts switch too", "A shortcut such as Ctrl+Cmd+Q also switches, unless Shift or Option is already held.")
            RowDivider(indented: true)
            fact("plus", "Add layouts in System Settings", "Keyboard > Text Input. With more than two, it goes back to the one used before.")
        }
    }

    private func fact(_ symbol: String, _ title: String, _ detail: String) -> some View {
        SettingsRow(title: title, subtitle: detail) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
        } trailing: {
            EmptyView()
        }
    }
}

/// The chord as two key caps, and the layouts it flips between.
private struct ChordPicture: View {
    let layouts: [String]
    let isActive: Bool

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                KeyCap(symbol: "⌃", name: "control")
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                KeyCap(symbol: "⌘", name: "command")
            }
            HStack(spacing: 10) {
                if layouts.isEmpty {
                    LayoutChip(name: "Your layouts show here while Language is on")
                } else {
                    ForEach(Array(layouts.prefix(2).enumerated()), id: \.offset) { index, name in
                        if index > 0 {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        LayoutChip(name: name)
                    }
                    if layouts.count > 2 {
                        LayoutChip(name: "+\(layouts.count - 2) more")
                    }
                }
            }
        }
        .opacity(isActive ? 1 : 0.55)
        .saturation(isActive ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Drawn like a modifier key on a Mac keyboard: the symbol top right, the name bottom left.
private struct KeyCap: View {
    let symbol: String
    let name: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Text(symbol).font(.system(size: 20, weight: .medium))
            }
            Spacer(minLength: 0)
            Text(name).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(dark ? Color.white : Color(white: 0.2))
        .padding(10)
        .frame(width: 96, height: 72)
        .background(
            shape.fill(dark ? Color(white: 0.2) : Color(white: 0.98))
                .shadow(color: .black.opacity(0.25), radius: 0, y: 3)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        )
        .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)))
    }
}

private struct LayoutChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassPanel(in: Capsule())
    }
}
