import AppKit
import InstantoolsCore
import SwiftUI

struct LanguagePane: View {
    let model: SettingsModel

    var body: some View {
        PaneScroll { _ in
            PaneHeader(pane: .language, subtitle: "Switch the keyboard layout with Control+Command, pressed in either order.")
            Hero {
                ChordPicture(layouts: model.layouts, current: model.currentLayout, isActive: model.isActive(.layoutSwitcher))
            } bar: {
                ToolStatusBar(model: model, tool: .layoutSwitcher, status: status, toggleLabel: "Use InstantLang for Control+Command")
            }
            if model.isEnabled(.layoutSwitcher), !model.inputMonitoringGranted {
                if model.inputMonitoringSwitchedOff {
                    Callout(
                        permission: .inputMonitoring,
                        title: "Input Monitoring is switched off",
                        message: "Turn it back on for Instantools, so InstantLang can see Control and Command."
                    )
                } else {
                    Callout(
                        permission: .inputMonitoring,
                        title: "Allow Input Monitoring",
                        message: "InstantLang needs it to see Control and Command. Allowing Accessibility for InstantTab covers it too."
                    )
                }
            }
            layouts
            TipsCard()
        }
    }

    private var status: (title: String, subtitle: String, color: Color) {
        guard model.isEnabled(.layoutSwitcher) else {
            return ("Off", "Control+Command does nothing for now.", .orange)
        }
        switch model.state(of: .layoutSwitcher) {
        case .failed(let reason):
            return ("InstantLang stopped", reason, .red)
        case .running where !model.isActive(.layoutSwitcher):
            let subtitle = model.inputMonitoringSwitchedOff
                ? "Turn Input Monitoring back on for Instantools." : "Allow Input Monitoring to start."
            return ("Waiting for permission", subtitle, .orange)
        case .running where model.layouts.count < 2:
            return ("Only one layout", "Add another in System Settings > Keyboard > Text Input.", .orange)
        case .running:
            return ("Control+Command switches the layout", "Press both, in either order, to go back to the last layout.", .green)
        case .starting, .off:
            return ("Starting", "Control+Command switches layouts once it is ready.", .orange)
        }
    }

    private var layouts: some View {
        SettingsCard(title: "Your layouts", footer: "Click a layout to switch to it. Emoji & Symbols and Dictation are skipped.") {
            if model.layouts.isEmpty { EmptyRow(text: "No keyboard layouts are turned on.") }
            DividedRows(model.layouts, id: \.id) { layout in
                LayoutRow(layout: layout, isCurrent: layout.id == model.currentLayout) { model.selectLayout(layout.id) }
            }
            RowDivider()
            SettingsRow(title: "Add or remove layouts", subtitle: "In System Settings, under Keyboard > Text Input.") {
                Button("Keyboard Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .glassButton()
            }
        }
    }
}

/// The chord as two key caps, and the layouts it switches between with the current one lit.
private struct ChordPicture: View {
    let layouts: [KeyboardLayout]
    let current: String?
    let isActive: Bool
    @Environment(\.compactLayout) private var compact

    var body: some View {
        VStack(spacing: compact ? 12 : 18) {
            HStack(spacing: 14) {
                KeyCap(symbol: "⌃", name: "control")
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                KeyCap(symbol: "⌘", name: "command")
            }
            VStack(spacing: 10) {
                FlowLayout(spacing: 10) {
                    ForEach(Array(layouts.enumerated()), id: \.element.id) { index, layout in
                        if index == 1, layouts.count == 2 {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .accessibilityHidden(true)
                        }
                        LayoutChip(name: layout.name, isCurrent: layout.id == current)
                    }
                }
                if layouts.count > 2 {
                    Text("With more than two, it goes back to the one used before.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 16)
        }
        .opacity(isActive ? 1 : 0.55)
        .saturation(isActive ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Drawn like a modifier key on a Mac keyboard: the symbol top right, the name bottom left. Smaller in a
/// compact hero, which is shorter, so wrapped layouts still fit below.
struct KeyCap: View {
    let symbol: String
    let name: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.compactLayout) private var compact

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
        .frame(width: compact ? 86 : 96, height: compact ? 62 : 72)
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
    let isCurrent: Bool

    var body: some View {
        let text = Text(name)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        Group {
            if isCurrent {
                text
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            } else {
                text.glassPanel(in: Capsule())
            }
        }
        .accessibilityValue(isCurrent ? "Current" : "")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct LayoutRow: View {
    let layout: KeyboardLayout
    let isCurrent: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                LayoutIcon(layout: layout)
                    .frame(width: Card.leadingWidth)
                Text(layout.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isCurrent {
                    Label("Current", systemImage: "checkmark")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, Card.inset)
            .padding(.vertical, 11)
            .background {
                if hovering, !isCurrent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(layout.name)
        .accessibilityValue(isCurrent ? "Current" : "")
        .accessibilityHint(isCurrent ? "" : "Switches to this layout")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Its own icon where it has one, as input modes do, else its language in a key-like outline.
private struct LayoutIcon: View {
    let layout: KeyboardLayout

    var body: some View {
        if let icon = layout.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        } else if let badge = layout.badge {
            Text(badge)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.secondary, lineWidth: 1.2))
        } else {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TipsCard: View {
    var body: some View {
        SettingsCard(title: "Tips") {
            VStack(alignment: .leading, spacing: 12) {
                Tip(
                    symbol: "arrow.left.arrow.right", title: "Either order",
                    detail: "Control first, Command first, or both at once. Left and right keys count the same."
                )
                Tip(symbol: "keyboard", title: "Typing never cancels it", detail: "Keys typed while both are still down never undo the switch.")
                Tip(
                    symbol: "command", title: "Shortcuts switch too",
                    detail: "Control+Command+Q and the like also switch, unless Shift or Option is already held."
                )
            }
            .padding(.vertical, 14)
            .padding(.horizontal, Card.inset)
        }
    }
}

private struct Tip: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: Card.leadingWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
