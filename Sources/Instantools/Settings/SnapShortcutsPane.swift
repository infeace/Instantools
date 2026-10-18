import InstantoolsKit
import SwiftUI
import WindowSnapperCore

struct SnapShortcutsPane: View {
    let model: SettingsModel

    var body: some View {
        let config = model.snapStore.config
        let taken = Set(model.unavailableSnapShortcuts)
        PaneScroll { _ in
            PaneHeader(pane: .snapShortcuts, subtitle: "The keys for each place a window can go. They start as Rectangle's, so there is nothing to relearn.")
            FileProblemBanner(configStore: model.snapStore)
            ForEach(SnapAction.groups, id: \.title) { group in
                SettingsCard(title: group.title, footer: group.footer) {
                    DividedRows(group.actions, id: \.self) { action in
                        ShortcutRow(action: action, shortcut: config.shortcut(for: action), isTaken: config.shortcut(for: action).map { taken.contains($0.text) } ?? false)
                    }
                }
            }
            SettingsCard(title: "Changing shortcuts") {
                SettingsRow(title: "Edit in the settings file", subtitle: "Each action takes keys such as ctrl+opt+left, or \"\" for none. Changes apply as soon as the file is saved.") {
                    Button("Open") { model.snapStore.openInEditor() }
                        .glassButton()
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let action: SnapAction
    let shortcut: Shortcut?
    let isTaken: Bool

    var body: some View {
        HStack(spacing: 12) {
            ActionGlyph(action: action)
                .frame(width: Card.leadingWidth)
            Text(action.title)
            Spacer(minLength: 12)
            if isTaken {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Another app has this shortcut, so it does nothing here.")
                    .accessibilityLabel("Taken by another app")
            }
            if let shortcut {
                Text(shortcut.symbols)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(isTaken ? 0.5 : 1)
                    .accessibilityLabel(shortcut.text)
            } else {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Card.inset)
        .padding(.vertical, 10)
    }
}

/// A small screen with the part the action takes filled in, or a symbol for the actions with no fixed place.
private struct ActionGlyph: View {
    let action: SnapAction

    var body: some View {
        switch action {
        case .center: symbol("dot.squareshape")
        case .restore: symbol("arrow.uturn.backward.square")
        case .previousDisplay: symbol("arrow.left.square")
        case .nextDisplay: symbol("arrow.right.square")
        default: region
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.tint)
    }

    private var region: some View {
        let size = CGSize(width: 26, height: 18)
        let screen = SnapScreen(frame: CGRect(origin: .zero, size: size), visible: CGRect(origin: .zero, size: size))
        let part = SnapLayout.frame(for: action, in: screen, gap: 0)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.2)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: max(part.width - 3, 1), height: max(part.height - 3, 1))
                .offset(x: part.minX + 1.5, y: part.minY + 1.5)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
