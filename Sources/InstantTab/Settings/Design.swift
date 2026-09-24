import AppKit
import SwiftUI

// Native controls inside cards and rows with consistent spacing. Liquid Glass is used only where Apple
// intends it, on controls floating above content, with a plain fallback before macOS 26.

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
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

struct PaneScroll<Content: View>: View {
    @ViewBuilder let content: (_ compact: Bool) -> Content
    @State private var width: CGFloat = 700

    var body: some View {
        let compact = width < 620
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content(compact)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, width < 560 ? 18 : 30)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.compactLayout, compact)
    }
}

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

/// Beside or stacked, keeping the children's identity when the layout switches.
func adaptiveLayout(compact: Bool, spacing: CGFloat = 16) -> AnyLayout {
    compact
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
}

struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @Environment(\.compactLayout) private var compact

    private let leadingWidth: CGFloat = 30
    private var hasLeading: Bool { Leading.self != EmptyView.self }

    var body: some View {
        let layout = adaptiveLayout(compact: compact)
        layout {
            HStack(spacing: 12) {
                if hasLeading { leading.frame(width: leadingWidth) }
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
            if !compact { Spacer(minLength: 12) }
            // Stacked under the text, not under the icon.
            trailing.padding(.leading, compact && hasLeading ? leadingWidth + 12 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

extension SettingsRow where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }
}

/// The last row of a list card. The buttons wrap onto their own lines when the row is too narrow.
struct CardActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
        .glassButton()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct RemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A card that asks for one action.
struct Callout: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let message: String
    let action: String
    let perform: () -> Void
    @Environment(\.compactLayout) private var compact

    var body: some View {
        let layout = adaptiveLayout(compact: compact, spacing: 12)
        let tint = colors.first ?? .accentColor
        HStack(alignment: compact ? .top : .center, spacing: 14) {
            IconTile(symbol: symbol, colors: colors, size: 34)
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !compact { Spacer(minLength: 0) }
                Button(action, action: perform)
                    .glassButton(prominent: true)
                    .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: Card.shape)
        .overlay(Card.shape.strokeBorder(tint.opacity(0.3)))
    }
}

enum Hero {
    static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
}

/// The desktop the hero previews sit on.
struct Wallpaper: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.13, green: 0.16, blue: 0.34), Color(red: 0.30, green: 0.16, blue: 0.40)]
                    : [Color(red: 0.55, green: 0.66, blue: 0.98), Color(red: 0.80, green: 0.62, blue: 0.95)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 360)
            }
    }
}

/// Floats on a hero. Stays on one or two lines so the hero keeps its height.
struct StatusBar<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassPanel(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

struct MessageRow: View {
    let text: String
    var isError = true

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
            .foregroundStyle(isError ? .red : .orange)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings is read-only while the file does not parse, so the file is never overwritten.
struct FileProblemBanner: View {
    let configStore: ConfigStore

    var body: some View {
        if configStore.fileIsBroken, let error = configStore.error {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The settings file has an error")
                        .font(.headline)
                    Text("Changes here are paused until it is fixed, so your file is never overwritten. \(error)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open File") { configStore.openInEditor() }
                        .glassButton()
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: Card.shape)
            .overlay(Card.shape.strokeBorder(Color.red.opacity(0.3)))
        }
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
    @ViewBuilder func glassPanel(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// Each pane shows its own title, so the toolbar drops it and content scrolls under the toolbar.
    @ViewBuilder func modernToolbar() -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: .title).toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }

    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
