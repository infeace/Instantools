import AppSwitcherCore
import InstantoolsCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case switcher
    case keys
    case monitors
    case exclusions
    case language
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .switcher: "Switcher"
        case .keys: "App keys"
        case .monitors: "Monitors"
        case .exclusions: "Excluded apps"
        case .language: "Layouts"
        case .about: "About"
        }
    }

    /// Nil for About, whose icon is the app's own.
    var tile: Tile? {
        switch self {
        case .general: .general
        case .switcher: .switcher
        case .keys: .keys
        case .monitors: .monitors
        case .exclusions: .exclusions
        case .language: .language
        case .about: nil
        }
    }
}

struct Tile {
    let symbol: String
    let colors: [Color]

    static let general = Tile(symbol: "gearshape.fill", colors: [Color(white: 0.62), Color(white: 0.45)])
    static let switcher = Tile(
        symbol: "command", colors: [Color(red: 0.66, green: 0.47, blue: 1), Color(red: 0.45, green: 0.26, blue: 0.9)]
    )
    static let keys = Tile(
        symbol: "keyboard.fill", colors: [Color(red: 0.36, green: 0.8, blue: 0.47), Color(red: 0.15, green: 0.6, blue: 0.32)]
    )
    static let monitors = Tile(
        symbol: "display.2", colors: [Color(red: 0.33, green: 0.62, blue: 1), Color(red: 0.13, green: 0.42, blue: 0.93)]
    )
    static let exclusions = Tile(
        symbol: "eye.slash.fill", colors: [Color(red: 1, green: 0.42, blue: 0.45), Color(red: 0.88, green: 0.2, blue: 0.33)]
    )
    static let language = Tile(
        symbol: "globe", colors: [Color(red: 0.25, green: 0.8, blue: 0.84), Color(red: 0.05, green: 0.56, blue: 0.68)]
    )
}

extension ToolId {
    /// In the sidebar under the tool, the first one being where its card on General leads.
    var panes: [SettingsPane] {
        switch self {
        case .appSwitcher: [.switcher, .keys, .monitors, .exclusions]
        case .layoutSwitcher: [.language]
        }
    }

    /// The icon of the pane that shows the tool stands for it.
    var tile: Tile {
        switch self {
        case .appSwitcher: .switcher
        case .layoutSwitcher: .language
        }
    }

    var inactiveStatus: String {
        switch self {
        case .appSwitcher: "macOS kept Cmd+Tab"
        case .layoutSwitcher: "Needs permission"
        }
    }
}

struct SettingsView: View {
    let model: SettingsModel
    @State private var selection: SettingsPane
    @State private var width = PaneWidth.wide

    init(model: SettingsModel, initialPane: SettingsPane = .general) {
        self.model = model
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            // Clicking empty sidebar space would otherwise clear the selection.
            List(selection: Binding(get: { selection }, set: { if let pane = $0 { selection = pane } })) {
                Section {
                    row(.general)
                }
                ForEach(ToolId.allCases) { tool in
                    Section {
                        ForEach(tool.panes) { pane in
                            row(pane)
                        }
                    } header: {
                        ToolSectionHeader(tool: tool, condition: model.condition(of: tool))
                    }
                }
                Section {
                    row(.about)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SidebarHeader(model: model)
            }
            // Only takes effect on the sidebar column, and must come before its width.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch selection {
                case .general: GeneralPane(model: model, open: { selection = $0 })
                case .switcher: SwitcherPane(model: model)
                case .keys: AppKeysPane(model: model)
                case .monitors: MonitorsPane(model: model)
                case .exclusions: ExclusionsPane(model: model)
                case .language: LanguagePane(model: model)
                case .about: AboutPane(model: model)
                }
            }
            .onGeometryChange(for: PaneWidth.self) { PaneWidth($0.size.width) } action: { width = $0 }
            .environment(\.paneWidth, width)
            .navigationTitle(selection.title)
        }
        .modernToolbar()
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            PaneIcon(pane: pane)
        }
        .tag(pane)
    }
}

private struct ToolSectionHeader: View {
    let tool: ToolId
    let condition: ToolCondition

    var body: some View {
        HStack(spacing: 6) {
            ToolIcon(tool: tool, size: 18)
            Text(tool.name)
            StatusDot(color: condition.color, size: 6)
                .padding(.leading, 1)
        }
        .help(condition.text(for: tool))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tool.name), \(condition.text(for: tool))")
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SidebarHeader: View {
    let model: SettingsModel

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Instantools")
                    .font(.headline)
                HStack(spacing: 5) {
                    StatusDot(color: summary.color)
                        .scaleEffect(0.8)
                    Text(summary.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var summary: (text: String, color: Color) {
        let enabled = ToolId.allCases.filter(model.isEnabled)
        if enabled.contains(where: { if case .failed = model.state(of: $0) { true } else { false } }) {
            return ("A tool stopped", .red)
        }
        if enabled.isEmpty { return ("All tools off", .orange) }
        if let inactive = enabled.first(where: { model.state(of: $0) == .running && !model.isActive($0) }) {
            return (inactive.inactiveStatus, .orange)
        }
        return enabled.allSatisfy(model.isActive) ? ("Active", .green) : ("Starting", .orange)
    }
}

struct ValueSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            // Rounded here because `step:` draws a tick mark per step.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range) {
                Text(label)
            }
            .labelsHidden()
            .frame(minWidth: 150, maxWidth: 210)
            Text(verbatim: "\(Int(value)) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
