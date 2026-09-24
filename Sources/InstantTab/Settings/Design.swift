import AppKit
import SwiftUI

// The building blocks every Settings pane is made of: native controls inside cards and rows that
// keep spacing and hierarchy consistent. Liquid Glass is used where Apple intends it (buttons and
// other controls that float above content), with a plain fallback before macOS 26.

/// A white symbol on a colored rounded square, as System Settings draws its panes.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
    }
}

/// The pane's icon: a tile, or the app icon for About.
struct PaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 20

    var body: some View {
        if pane == .about {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: size * 1.2, height: size * 1.2)
                .frame(width: size, height: size)
        } else {
            IconTile(symbol: pane.symbol, colors: pane.colors, size: size)
        }
    }
}

struct PaneHeader: View {
    let pane: SettingsPane
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(pane.title)
                .font(.system(size: 28, weight: .bold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the pane is narrow: rows stack their control under the text instead of beside it.
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

/// The scrolling page every pane lives in. It keeps a comfortable reading width on wide windows and
/// switches rows to a stacked layout on narrow ones.
struct PaneScroll<Content: View>: View {
    /// Receives whether the layout is compact, for sections laid out by the pane itself.
    @ViewBuilder let content: (_ compact: Bool) -> Content
    @State private var width: CGFloat = 700

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content(width < 620)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, width < 560 ? 18 : 30)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.compactLayout, width < 620)
    }
}

/// A titled group of rows.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
            }
            .background(Card.fill, in: Card.shape)
            .overlay(Card.shape.strokeBorder(Card.stroke))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

enum Card {
    static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    static let fill = Color.primary.opacity(0.04)
    static let stroke = Color.primary.opacity(0.07)
}

/// A title, an optional explanation, and a control: beside the text, or under it when narrow.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing
    @Environment(\.compactLayout) private var compact

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 10) {
                    labels
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    labels
                    Spacer(minLength: 12)
                    trailing
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

extension View {
    /// A Liquid Glass surface for controls floating above content, a material before macOS 26.
    @ViewBuilder func glassPanel(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// No duplicate title in the toolbar (each pane has its own), and content scrolls under it.
    @ViewBuilder func modernToolbar() -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: .title).toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }

    /// Liquid Glass buttons on macOS 26, bordered ones before.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
