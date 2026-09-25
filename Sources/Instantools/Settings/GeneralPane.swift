import AppSwitcherKit
import InstantoolsCore
import SwiftUI

struct GeneralPane: View {
    let model: SettingsModel
    let open: (SettingsPane) -> Void

    var body: some View {
        PaneScroll { compact in
            PaneHeader(pane: .general, subtitle: "Choose the tools you want. Each runs in its own process, so one never slows or stops another.")
            tools(stacked: compact)
            startup
            configuration
        }
    }

    private func tools(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return CardSection(
            title: "Tools",
            footer: model.enabledTools.isEmpty
                ? nil : "Every tool runs as part of Instantools, so macOS asks once and lists only Instantools in Privacy & Security."
        ) {
            layout {
                ForEach(ToolId.allCases) { tool in
                    ToolCard(tool: tool, model: model, stacked: stacked) { open(tool.panes[0]) }
                }
            }
            // Side by side, both cards take the height of the taller one.
            .fixedSize(horizontal: false, vertical: true)
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
            SettingsRow(title: "Settings folder", subtitle: "\(ConfigStore.directory.abbreviatedPath), kept in sync with this window.") {
                Button("Show in Finder") { ConfigStore.revealDirectory() }
                    .glassButton()
            }
        }
    }
}

/// A tool with its switch, what it lacks right now, and the way to its own settings. Side by side the icon
/// sits above the name, stacked beside it.
private struct ToolCard: View {
    let tool: ToolId
    let model: SettingsModel
    let stacked: Bool
    let open: () -> Void

    var body: some View {
        let condition = model.condition(of: tool)
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if stacked {
                    HStack(spacing: 14) {
                        ToolIcon(tool: tool, size: 56)
                        text(condition)
                        Spacer(minLength: 8)
                        toggle
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            ToolIcon(tool: tool, size: 60)
                            Spacer(minLength: 8)
                            toggle
                        }
                        text(condition)
                    }
                }
            }
            .padding(Card.inset)

            if case .failed(let reason) = condition {
                RowDivider()
                FailureRow(reason: reason) { model.retry(tool) }
            }
            ForEach(model.missingPermissions(of: tool), id: \.self) { permission in
                RowDivider()
                MissingPermissionRow(permission: permission, subtitle: permission.reason(for: tool, model.permissions))
            }
            Spacer(minLength: 0)
            RowDivider()
            Button(action: open) {
                HStack(spacing: 3) {
                    Text("Open \(tool.panes[0].title)")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.link)
            .padding(.horizontal, Card.inset)
            .padding(.vertical, 11)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground()
    }

    private func text(_ condition: ToolCondition) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tool.name)
                .font(.title3.weight(.semibold))
            Text(tool.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                StatusDot(color: condition.color, size: 7)
                Text(condition.text(for: tool))
                    .font(.callout)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var toggle: some View {
        Toggle("Use \(tool.name)", isOn: model.enabled(tool))
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

private struct FailureRow: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again", action: retry)
                .glassButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Card.inset)
        .padding(.vertical, 12)
    }
}

/// The button sits beside the title rather than the text, so the text keeps the card's width.
private struct MissingPermissionRow: View {
    let permission: Permission
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconTile(permission.tile, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(permission.title)
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 8)
                    Button("Allow…", action: permission.request)
                        .glassButton(prominent: true)
                        .controlSize(.small)
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Card.inset)
        .padding(.vertical, 12)
    }
}
