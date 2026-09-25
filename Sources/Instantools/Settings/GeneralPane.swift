import AppSwitcherKit
import InstantoolsCore
import SwiftUI

struct GeneralPane: View {
    let model: SettingsModel

    var body: some View {
        PaneScroll { _ in
            PaneHeader(pane: .general, subtitle: "Choose the tools you want. Each runs in its own process, so one never slows or stops another.")
            tools
            if !model.enabledTools.isEmpty { permissions }
            startup
            configuration
        }
    }

    private var tools: some View {
        SettingsCard(title: "Tools") {
            DividedRows(ToolId.allCases, id: \.self) { tool in
                ToolRow(tool: tool, model: model)
            }
        }
    }

    private var permissions: some View {
        SettingsCard(
            title: "Permissions",
            footer: "Every tool runs as part of Instantools, so macOS asks once and lists only Instantools in Privacy & Security."
        ) {
            PermissionRow(permission: .accessibility, subtitle: accessibilitySubtitle, granted: model.accessibilityGranted)
            if model.needsInputMonitoring {
                RowDivider(indented: true)
                PermissionRow(permission: .inputMonitoring, subtitle: inputMonitoringSubtitle, granted: model.inputMonitoringGranted)
            }
        }
    }

    private var accessibilitySubtitle: String {
        let switchedOff = model.inputMonitoringSwitchedOff
        if model.isEnabled(.appSwitcher) {
            let covers = switchedOff ? "" : " It covers Language too."
            return "Cmd+Tab needs it for the keys inside the switcher and to bring the right window forward.\(covers)"
        }
        return switchedOff
            ? "Not enough for Language while Input Monitoring is switched off."
            : "Lets Language see Control and Command, in place of Input Monitoring."
    }

    private var inputMonitoringSubtitle: String {
        guard model.inputMonitoringSwitchedOff else {
            return "Lets Language see Control and Command. Allowing Accessibility covers it too."
        }
        let tools = ToolId.allCases.filter(model.isEnabled).map(\.name).formatted(.list(type: .and))
        return "Switched off for Instantools, so \(tools) cannot see keys until it is back on."
    }

    private var startup: some View {
        SettingsCard(title: "Startup") {
            SettingsRow(title: "Start at login", subtitle: "Takes effect at your next login. Instantools then also comes back by itself if it ever crashes.") {
                Toggle("Start at login", isOn: model.startAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if model.loginBlocked {
                RowDivider()
                SettingsRow(title: "Turned off in Login Items", subtitle: "macOS will not start Instantools until you allow it again.") {
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
            SettingsRow(title: "Settings folder", subtitle: "\(ConfigStore.directory.abbreviatedPath), kept in sync with this window.") {
                Button("Show in Finder") { ConfigStore.revealDirectory() }
                    .glassButton()
            }
        }
    }
}

private struct ToolRow: View {
    let tool: ToolId
    let model: SettingsModel

    var body: some View {
        let state = model.state(of: tool)
        SettingsRow(title: tool.name, subtitle: tool.summary) {
            ToolIcon(tool: tool)
        } trailing: {
            HStack(spacing: 12) {
                ToolStatusLabel(tool: tool, model: model)
                Toggle("Use \(tool.name)", isOn: model.enabled(tool))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        if case .failed(let reason) = state, model.isEnabled(tool) {
            HStack(spacing: 12) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Try Again") { model.retry(tool) }
                    .glassButton()
            }
            .padding(.leading, Card.textInset)
            .padding(.trailing, Card.inset)
            .padding(.bottom, 12)
        }
    }
}

private struct ToolStatusLabel: View {
    let tool: ToolId
    let model: SettingsModel

    var body: some View {
        let (text, color) = status
        HStack(spacing: 6) {
            StatusDot(color: color)
                .scaleEffect(0.8)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private var status: (text: String, color: Color) {
        switch model.state(of: tool) {
        case .running where model.isActive(tool): ("Running", .green)
        case .running: (tool.inactiveStatus, .orange)
        case .failed: ("Failed", .red)
        case .starting, .off: model.isEnabled(tool) ? ("Starting", .orange) : ("Off", Color(white: 0.6))
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let subtitle: String
    let granted: Bool

    var body: some View {
        SettingsRow(title: permission.title, subtitle: subtitle) {
            IconTile(permission.tile, size: 30)
        } trailing: {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fixedSize()
            } else {
                Button("Allow…", action: permission.request)
                    .glassButton(prominent: true)
            }
        }
    }
}
