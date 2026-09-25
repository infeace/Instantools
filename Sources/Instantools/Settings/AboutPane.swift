import AppSwitcherKit
import InstantoolsCore
import SwiftUI

struct AboutPane: View {
    let model: SettingsModel

    var body: some View {
        PaneScroll { _ in
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                Text("Instantools")
                    .font(.largeTitle.weight(.semibold))
                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .foregroundStyle(.secondary)
                Text("Mac tools that respond the moment you press them.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                HStack(spacing: 10) {
                    Button {
                        model.openRepository()
                    } label: {
                        Label("View on GitHub", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        ConfigStore.revealDirectory()
                    } label: {
                        Label("Show Settings Folder", systemImage: "folder")
                    }
                }
                .glassButton()
                .controlSize(.large)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            SettingsCard(title: "Tools") {
                DividedRows(ToolId.allCases, id: \.self) { tool in
                    SettingsRow(title: tool.name, subtitle: tool.summary) {
                        ToolIcon(tool: tool)
                    } trailing: {
                        EmptyView()
                    }
                }
            }

            SettingsCard(title: "How it stays fast") {
                FactRow("bolt.fill", "Nothing is looked up when you press a key", "Apps, windows and layouts are tracked in the background, so a key press only reads memory.")
                RowDivider(indented: true)
                FactRow("square.split.2x1.fill", "Each tool runs in its own process", "One never slows or stops another, and each keeps working while Instantools itself restarts.")
                RowDivider(indented: true)
                FactRow("rectangle.stack.fill", "The switcher is built once", "It is drawn at launch and reused, so showing it costs a few milliseconds.")
                RowDivider(indented: true)
                FactRow("arrow.uturn.backward", "Native Cmd+Tab always comes back", "Quitting, pausing or a crash hands Cmd+Tab back to macOS.")
            }

            Text("Focus handling follows techniques pioneered by yabai, AltTab and Hammerspoon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
