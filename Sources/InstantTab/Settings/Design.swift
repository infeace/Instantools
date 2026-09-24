import AppKit
import SwiftUI

struct IconTile: View {
    let symbol: String
    let colors: [Color]
    let size: CGFloat

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

    var body: some View {
        if pane == .about {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
                .frame(width: 20, height: 20)
        } else {
            IconTile(symbol: pane.symbol, colors: pane.colors, size: 20)
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

/// Measured once for the detail column, so panes do not re-render on every pixel of a resize.
enum PaneWidth {
    case narrow
    case compact
    case wide

    init(_ width: CGFloat) {
        self = width < 560 ? .narrow : width < 620 ? .compact : .wide
    }
}

private struct PaneWidthKey: EnvironmentKey {
    static let defaultValue = PaneWidth.wide
}

private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var paneWidth: PaneWidth {
        get { self[PaneWidthKey.self] }
        set { self[PaneWidthKey.self] = newValue }
    }

    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

struct PaneScroll<Content: View>: View {
    @ViewBuilder let content: (_ compact: Bool) -> Content
    @Environment(\.paneWidth) private var width

    var body: some View {
        let compact = width != .wide
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content(compact)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, width == .narrow ? 18 : 30)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .environment(\.compactLayout, compact)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
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
    static let inset: CGFloat = 16
    /// Where row text starts when the row has a leading icon.
    static let textInset: CGFloat = inset + leadingWidth + 12
    static let leadingWidth: CGFloat = 30
}

/// Beside or stacked, keeping the children's identity when the layout switches.
func adaptiveLayout(compact: Bool, spacing: CGFloat = 16) -> AnyLayout {
    compact
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
}

struct SettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @Environment(\.compactLayout) private var compact

    private var hasLeading: Bool { Leading.self != EmptyView.self }

    var body: some View {
        let layout = adaptiveLayout(compact: compact)
        layout {
            HStack(spacing: 12) {
                if hasLeading { leading.frame(width: Card.leadingWidth) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !compact { Spacer(minLength: 12) }
            // Stacked under the text, not under the icon.
            trailing.padding(.leading, compact && hasLeading ? Card.textInset - Card.inset : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Card.inset)
        .padding(.vertical, 12)
    }
}

extension SettingsRow where Leading == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

/// Lines up with the row text, like System Settings.
struct RowDivider: View {
    var indented = false

    var body: some View {
        Divider().padding(.leading, indented ? Card.textInset : Card.inset)
    }
}

struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Card.inset)
    }
}

struct CardActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        RowDivider()
        HStack(spacing: 8) { content }
            .glassButton()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Card.inset)
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

struct MessageRow: View {
    let text: String
    var isError = true

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
            .foregroundStyle(isError ? .red : .orange)
            .padding(.horizontal, Card.inset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Callout: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let message: String
    let action: String
    var prominent = true
    let perform: () -> Void
    @Environment(\.compactLayout) private var compact

    var body: some View {
        let layout = adaptiveLayout(compact: compact, spacing: 12)
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
                    .glassButton(prominent: prominent)
                    .controlSize(.large)
            }
        }
        .padding(Card.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors[0].opacity(0.08), in: Card.shape)
        .overlay(Card.shape.strokeBorder(colors[0].opacity(0.3)))
    }
}

/// Shown on every pane. A file that does not parse makes Settings read-only, so it is never overwritten.
struct FileProblemBanner: View {
    let configStore: ConfigStore

    var body: some View {
        if let error = configStore.error {
            Callout(
                symbol: "exclamationmark.triangle.fill",
                colors: [.red, Color(red: 0.8, green: 0.1, blue: 0.15)],
                title: configStore.fileIsBroken ? "The settings file has an error" : "Settings could not be saved",
                message: configStore.fileIsBroken ? "Changes here are paused until it is fixed. \(error)" : error,
                action: "Open File",
                prominent: false,
                perform: configStore.openInEditor
            )
        }
    }
}

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

struct Hero<Picture: View, Bar: View>: View {
    @ViewBuilder let picture: Picture
    @ViewBuilder let bar: Bar
    @Environment(\.compactLayout) private var compact

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 12) {
            picture.frame(height: compact ? 170 : 200)
            bar
        }
        .padding(12)
        .background(Wallpaper())
        .clipShape(shape)
        .overlay(shape.strokeBorder(Card.stroke))
    }
}

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
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Card.inset)
        .padding(.vertical, 11)
        .glassPanel(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension StatusBar where Trailing == EmptyView {
    init(title: String, subtitle: String?, @ViewBuilder leading: () -> Leading) {
        self.init(title: title, subtitle: subtitle, leading: leading, trailing: { EmptyView() })
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

struct GroupDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
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
