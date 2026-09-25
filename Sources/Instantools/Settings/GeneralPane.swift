import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit
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
            ForEach(Array(ToolId.allCases.enumerated()), id: \.element) { index, tool in
                if index > 0 { RowDivider(indented: true) }
                ToolRow(tool: tool, model: model)
            }
        }
    }

    private var permissions: some View {
        SettingsCard(
            title: "Permissions",
            footer: "Every tool runs as part of Instantools, so macOS asks once and lists only Instantools in Privacy & Security."
        ) {
            PermissionRow(
                symbol: "hand.raised.fill",
                colors: [.orange, Color(red: 0.93, green: 0.42, blue: 0.1)],
                title: "Accessibility",
                subtitle: model.isEnabled(.appSwitcher)
                    ? "Cmd+Tab needs it for the keys inside the switcher and to bring the right window forward. It covers Language too."
                    : "Lets Language see Control and Command, in place of Input Monitoring.",
                granted: model.accessibilityGranted,
                allow: Permissions.requestAccessibilityInSettings
            )
            if model.isEnabled(.layoutSwitcher), !model.accessibilityGranted {
                RowDivider(indented: true)
                PermissionRow(
                    symbol: "keyboard.fill",
                    colors: SettingsPane.language.colors,
                    title: "Input Monitoring",
                    subtitle: "Lets Language see Control and Command. Not needed once Accessibility is allowed.",
                    granted: model.inputMonitoringGranted,
                    allow: Permissions.requestInputMonitoringInSettings
                )
            }
        }
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
            SettingsRow(title: "Settings folder", subtitle: "~/.config/instantools, one file per tool, kept in sync with this window.") {
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
            IconTile(symbol: tool.pane.symbol, colors: tool.pane.colors, size: 30)
        } trailing: {
            HStack(spacing: 12) {
                ToolStatusLabel(state: state, isEnabled: model.isEnabled(tool))
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

private struct PermissionRow: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let subtitle: String
    let granted: Bool
    let allow: () -> Void

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            IconTile(symbol: symbol, colors: colors, size: 30)
        } trailing: {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fixedSize()
            } else {
                Button("Allow…", action: allow)
                    .glassButton(prominent: true)
            }
        }
    }
}
