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
                Text("InstantTab")
                    .font(.largeTitle.weight(.semibold))
                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .foregroundStyle(.secondary)
                Text("Cmd+Tab that appears the moment you press it, with the control macOS leaves out.")
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
                        model.configStore.revealInFinder()
                    } label: {
                        Label("Settings File", systemImage: "doc.text")
                    }
                }
                .glassButton()
                .controlSize(.large)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            SettingsCard(title: "How it stays fast") {
                fact("bolt.fill", "Nothing is looked up when you press Tab", "Apps and windows are tracked in the background, so the switcher only reads memory.")
                RowDivider()
                fact("rectangle.stack.fill", "The switcher is built once", "It is drawn at launch and reused, so showing it costs a few milliseconds.")
                RowDivider()
                fact("arrow.uturn.backward", "Native Cmd+Tab always comes back", "Quitting, pausing or a crash hands Cmd+Tab back to macOS.")
            }

            Text("Focus handling follows techniques pioneered by yabai, AltTab and Hammerspoon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
    }

    private func fact(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
    }
}
