import AppKit
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit
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

extension IconTile {
    init(_ tile: Tile, size: CGFloat) {
        self.init(symbol: tile.symbol, colors: tile.colors, size: size)
    }
}

struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        if let tile = pane.tile {
            IconTile(tile, size: 20)
        } else {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
                .frame(width: 20, height: 20)
        }
    }
}

struct ToolIcon: View {
    let tool: ToolId
    var size: CGFloat = 30

    var body: some View {
        if let icon = ToolIcons.image(for: tool) {
            // Its square is 824 of its 1024 points, so it is drawn larger to line up with tiles of the same size.
            let drawn = (size * 1024 / 824).rounded()
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: drawn, height: drawn)
                .frame(width: size, height: size)
        } else {
            IconTile(tool.tile, size: size)
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
        CardSection(title: title, footer: footer) {
            VStack(spacing: 0) {
                content
            }
            .cardBackground()
        }
    }
}

/// A title and a footer around cards of its own, as SettingsCard has around its rows.
struct CardSection<Content: View>: View {
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
            content
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

struct DividedRows<Data: RandomAccessCollection, ID: Hashable, Row: View>: View {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    @ViewBuilder let row: (Data.Element) -> Row

    init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.id = id
        self.row = row
    }

    var body: some View {
        let first = data.first?[keyPath: id]
        ForEach(data, id: id) { element in
            if element[keyPath: id] != first { RowDivider(indented: true) }
            row(element)
        }
    }
}

struct FactRow: View {
    let symbol: String
    let title: String
    let detail: String

    init(_ symbol: String, _ title: String, _ detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    var body: some View {
        SettingsRow(title: title, subtitle: detail) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
        } trailing: {
            EmptyView()
        }
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

/// An app's icon in a row, or a stand-in when the app is not installed or the id is a pattern.
struct AppIcon: View {
    let info: AppLookup.Info
    var isPattern = false

    var body: some View {
        Group {
            if let icon = info.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: isPattern ? "square.stack.3d.up" : "questionmark.app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 30)
    }
}

struct RunningAppMenu: View {
    let apps: [SettingsModel.AppChoice]
    let add: (String) -> Void

    var body: some View {
        Menu("Add Running App") {
            ForEach(apps, id: \.bundleId) { app in
                Button { add(app.bundleId) } label: { AppChoiceLabel(app: app) }
            }
        }
        .fixedSize()
        .disabled(apps.isEmpty)
    }
}

private struct AppChoiceLabel: View {
    let app: SettingsModel.AppChoice

    var body: some View {
        if let icon = AppLookup.menuIcon(app.icon) {
            Label { Text(app.name) } icon: { Image(nsImage: icon) }
        } else {
            Text(app.name)
        }
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

extension Callout {
    init(permission: Permission, title: String, message: String) {
        self.init(
            symbol: permission.tile.symbol, colors: permission.tile.colors, title: title, message: message,
            action: "Allow…", perform: permission.request
        )
    }
}

extension Permission {
    /// Input Monitoring wears Language's colors, since Language is what needs it most.
    var tile: Tile {
        switch self {
        case .accessibility: Tile(symbol: "hand.raised.fill", colors: [.orange, Color(red: 0.93, green: 0.42, blue: 0.1)])
        case .inputMonitoring: Tile(symbol: "keyboard.fill", colors: Tile.language.colors)
        }
    }

    func request() {
        switch self {
        case .accessibility: Permissions.requestAccessibilityInSettings()
        case .inputMonitoring: Permissions.requestInputMonitoringInSettings()
        }
    }

    /// Why a tool needs it, on the tool's card on General and in the welcome.
    func reason(for tool: ToolId, _ state: PermissionState) -> String {
        switch (tool, self) {
        case (.appSwitcher, .accessibility):
            let covers = state.inputMonitoringSwitchedOff ? "" : " It covers InstantLang too."
            return "Needed for the keys inside the switcher and to bring the right window forward.\(covers)"
        case (.appSwitcher, .inputMonitoring):
            return "Switched off for Instantools, so the keys inside the switcher do nothing until it is back on."
        case (.layoutSwitcher, _):
            return state.inputMonitoringSwitchedOff
                ? "Switched off for Instantools, so InstantLang cannot see Control and Command until it is back on."
                : "Lets InstantLang see Control and Command. Allowing Accessibility covers it too."
        }
    }
}

/// Shown on the Cmd+Tab panes, for a file that does not parse and for a save that failed. While the file
/// does not parse their controls are disabled, so only Reset can replace it.
struct FileProblemBanner: View {
    let configStore: ConfigStore

    var body: some View {
        if let error = configStore.error {
            Callout(
                symbol: "exclamationmark.triangle.fill",
                colors: [.red, Color(red: 0.8, green: 0.1, blue: 0.15)],
                title: configStore.fileIsBroken ? "The settings file has an error" : "Settings could not be saved",
                message: configStore.fileIsBroken ? "Changes here are paused until it is fixed.\n\(error)" : error,
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

struct ToolStatusBar: View {
    let model: SettingsModel
    let tool: ToolId
    let status: (title: String, subtitle: String, color: Color)
    let toggleLabel: String
    @Environment(\.compactLayout) private var compact

    var body: some View {
        StatusBar(title: status.title, subtitle: compact ? nil : status.subtitle) {
            StatusDot(color: status.color)
        } trailing: {
            HStack(spacing: 10) {
                if case .failed = model.state(of: tool) {
                    Button("Try Again") { model.retry(tool) }
                        .glassButton()
                }
                Toggle(toggleLabel, isOn: model.enabled(tool))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.6), radius: size * 0.375)
    }
}

extension ToolCondition {
    var color: Color {
        switch self {
        case .active: .green
        case .inactive, .starting: .orange
        case .off: Color(white: 0.6)
        case .failed: .red
        }
    }

    func text(for tool: ToolId) -> String {
        switch self {
        case .active: "Running"
        case .inactive: tool.inactiveStatus
        case .starting: "Starting…"
        case .off: "Off"
        case .failed: "Failed"
        }
    }
}

/// Rows that wrap like lines of text, each centered.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(of: subviews, within: proposal.width ?? .infinity)
        let rows = rows(of: sizes, within: proposal.width ?? .infinity)
        let widths = rows.map { row in row.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(row.count - 1) }
        let height = rows.reduce(0) { total, row in total + (row.map { sizes[$0].height }.max() ?? 0) }
        return CGSize(width: widths.max() ?? 0, height: height + lineSpacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(of: subviews, within: bounds.width)
        var y = bounds.minY
        for row in rows(of: sizes, within: bounds.width) {
            let width = row.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(row.count - 1)
            let height = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.midX - width / 2
            for index in row {
                let size = sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + lineSpacing
        }
    }

    /// Never wider than a row, so a long name truncates rather than overflows.
    private func sizes(of subviews: Subviews, within width: CGFloat) -> [CGSize] {
        subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            return size.width <= width ? size : subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
    }

    private func rows(of sizes: [CGSize], within width: CGFloat) -> [Range<Int>] {
        FlowRows.rows(widths: sizes.map { Double($0.width) }, maxWidth: Double(width), spacing: Double(spacing))
    }
}

struct GroupDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

extension URL {
    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

extension View {
    func cardBackground() -> some View {
        background(Card.fill, in: Card.shape)
            .overlay(Card.shape.strokeBorder(Card.stroke))
    }

    /// Liquid Glass needs the macOS 26 SDK, which came with Swift 6.2. Built with older tools, Settings keeps
    /// the look it has before macOS 26.
    @ViewBuilder func glassPanel(in shape: some Shape) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
        #else
        background(.regularMaterial, in: shape)
        #endif
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
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
        #else
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #endif
    }
}
