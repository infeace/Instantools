import AppKit
import InstantoolsCore
import SwiftUI

struct WelcomeView: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            // In the title bar, level with the window buttons, where the hidden title would be.
            StepIndicator(current: model.step, chosen: model.chosen)
                .frame(height: 32)
            Group {
                switch model.step {
                case .tools: ToolsStep(model: model)
                case .permissions: PermissionsStep(model: model)
                case .done: DoneStep(model: model)
                }
            }
            .id(model.step)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 24)
            Divider()
            BottomBar(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }
}

extension WelcomeStep {
    var title: String {
        switch self {
        case .tools: "Tools"
        case .permissions: "Access"
        case .done: "Ready"
        }
    }
}

private struct StepIndicator: View {
    let current: WelcomeStep
    let chosen: Set<ToolId>

    var body: some View {
        let steps = WelcomeStep.allCases
        let currentIndex = steps.firstIndex(of: current) ?? 0
        HStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                if index > 0 {
                    Capsule()
                        .fill(index <= currentIndex ? AnyShapeStyle(Color.accentColor.opacity(0.5)) : AnyShapeStyle(.quaternary))
                        .frame(width: 22, height: 2)
                }
                item(step, number: index + 1, index: index, currentIndex: currentIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(steps.count), \(current.title)")
    }

    private func item(_ step: WelcomeStep, number: Int, index: Int, currentIndex: Int) -> some View {
        let isCurrent = index == currentIndex
        let passed = index < currentIndex && !step.isSkipped(choosing: chosen)
        let filled = isCurrent || passed
        return HStack(spacing: 6) {
            ZStack {
                if filled {
                    Circle().fill(Color.accentColor)
                } else {
                    Circle().strokeBorder(.tertiary, lineWidth: 1.5)
                }
                if passed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
            }
            .frame(width: 20, height: 20)
            Text(step.title)
                .font(.callout.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }
}

private struct StepHeader<Icon: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 0) {
            // The same height on every step, so the titles do not move between them.
            icon.frame(height: 80)
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ToolsStep: View {
    let model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Welcome to Instantools", subtitle: "Mac tools that respond the moment you press them. Pick the ones you want.") {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            HStack(spacing: 16) {
                ForEach(ToolId.allCases) { tool in
                    ToolChoice(tool: tool, isOn: model.isChosen(tool)) { model.toggle(tool) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 30)
            Text(model.chosen.isEmpty
                ? "Nothing runs for now. You can turn a tool on any time in Settings."
                : "Each runs in its own process, so one never slows or stops another.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
        }
    }
}

/// The whole card toggles the tool.
private struct ToolChoice: View {
    let tool: ToolId
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ToolIcon(tool: tool, size: 56)
                    Spacer(minLength: 8)
                    checkmark
                }
                Text(tool.name)
                    .font(.title3.weight(.semibold))
                    .padding(.top, 14)
                Text(tool.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isOn ? Color.accentColor.opacity(0.07) : Card.fill, in: Card.shape)
            .overlay(Card.shape.strokeBorder(isOn ? Color.accentColor : Card.stroke, lineWidth: isOn ? 2 : 1))
            .contentShape(Card.shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tool.name)
        .accessibilityHint(tool.tagline)
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }

    @ViewBuilder private var checkmark: some View {
        if isOn {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct PermissionsStep: View {
    let model: WelcomeModel

    var body: some View {
        let needs = model.needs
        let state = model.permissions ?? PermissionState(accessibility: false, inputMonitoring: false)
        VStack(spacing: 0) {
            StepHeader(
                title: "Allow access",
                subtitle: "Your tools need these to see the keys you press.\nIn System Settings, they all appear as Instantools."
            ) {
                IconTile(symbol: "hand.raised.fill", colors: Tile.monitors.colors, size: 64)
            }
            VStack(spacing: 0) {
                if needs.isEmpty {
                    SettingsRow(title: "Nothing to allow", subtitle: "Your tools already have the access they need.") {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                    } trailing: {
                        EmptyView()
                    }
                }
                DividedRows(needs, id: \.permission) { need in
                    PermissionRow(
                        permission: need.permission, reason: need.permission.reason(for: need.tool, state),
                        granted: model.permissions?.isGranted(need.permission)
                    )
                }
            }
            .cardBackground()
            .padding(.top, 28)
            if !needs.isEmpty {
                Text("macOS may also ask in a window of its own. You can allow these later in Settings too.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .padding(.horizontal, 12)
            }
        }
        .animation(.smooth(duration: 0.3), value: needs)
        .animation(.smooth(duration: 0.3), value: model.permissions)
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let reason: String
    /// Nil while the first check is still out, when the row shows neither.
    let granted: Bool?

    var body: some View {
        SettingsRow(title: permission.title, subtitle: reason) {
            IconTile(permission.tile, size: 30)
        } trailing: {
            switch granted {
            case true?:
                Label {
                    Text("Allowed")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .transition(.opacity)
            case false?:
                Button("Allow…", action: permission.request)
                    .glassButton(prominent: true)
                    .transition(.opacity)
            case nil:
                EmptyView()
            }
        }
    }
}

private struct DoneStep: View {
    let model: WelcomeModel

    var body: some View {
        let tools = ToolId.allCases.filter { model.isChosen($0) }
        VStack(spacing: 0) {
            StepHeader(
                title: "You're set",
                subtitle: tools.isEmpty
                    ? "Instantools waits in the menu bar. Turn on a tool there or in Settings whenever you like."
                    : "Instantools waits in the menu bar. Try your tools now."
            ) {
                IconTile(symbol: "checkmark", colors: Tile.keys.colors, size: 64)
            }
            if !tools.isEmpty {
                HStack(spacing: 16) {
                    ForEach(tools) { tool in
                        TryIt(tool: tool)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 26)
            }
            VStack(spacing: 0) {
                SettingsRow(title: "Start at login", subtitle: "Instantools also comes back by itself if it ever crashes.") {
                    Toggle("Start at login", isOn: Binding(get: { model.startAtLogin }, set: { model.startAtLogin = $0 }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if let error = model.loginError {
                    RowDivider()
                    MessageRow(text: error)
                }
            }
            .cardBackground()
            .padding(.top, tools.isEmpty ? 28 : 16)
        }
    }
}

private struct TryIt: View {
    let tool: ToolId

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    KeyCap(symbol: key.symbol, name: key.name)
                }
            }
            .environment(\.compactLayout, true)
            .accessibilityHidden(true)
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    ToolIcon(tool: tool, size: 16)
                    Text(tool.name)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Text(line)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardBackground()
    }

    private var keys: [(symbol: String, name: String)] {
        switch tool {
        case .appSwitcher: [("⌘", "command"), ("⇥", "tab")]
        case .layoutSwitcher: [("⌃", "control"), ("⌘", "command")]
        }
    }

    private var line: String {
        switch tool {
        case .appSwitcher: "Hold Cmd and press Tab"
        case .layoutSwitcher: "Press Control and Command together"
        }
    }
}

private struct BottomBar: View {
    let model: WelcomeModel

    var body: some View {
        HStack(spacing: 10) {
            button("Back") { model.goBack() }
                .opacity(model.step == .tools ? 0 : 1)
                .disabled(model.step == .tools)
                .accessibilityHidden(model.step == .tools)
            Spacer()
            if model.step == .done {
                button("Open Settings") { model.finish(openingSettings: true) }
                button("Done") { model.finish(openingSettings: false) }
                    .glassButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
            } else {
                button("Continue") { model.goOn() }
                    .glassButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .glassButton()
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { action() }
        } label: {
            Text(title).frame(minWidth: 64)
        }
    }
}
