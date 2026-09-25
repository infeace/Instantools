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
        case .keys: "App Keys"
        case .monitors: "Monitors"
        case .exclusions: "Excluded Apps"
        case .language: "Language"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .switcher: "command"
        case .keys: "keyboard.fill"
        case .monitors: "display.2"
        case .exclusions: "eye.slash.fill"
        case .language: "globe"
        case .about: "info"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: [Color(white: 0.62), Color(white: 0.45)]
        case .switcher: [Color(red: 0.66, green: 0.47, blue: 1), Color(red: 0.45, green: 0.26, blue: 0.9)]
        case .keys: [Color(red: 0.36, green: 0.8, blue: 0.47), Color(red: 0.15, green: 0.6, blue: 0.32)]
        case .monitors: [Color(red: 0.33, green: 0.62, blue: 1), Color(red: 0.13, green: 0.42, blue: 0.93)]
        case .exclusions: [Color(red: 1, green: 0.42, blue: 0.45), Color(red: 0.88, green: 0.2, blue: 0.33)]
        case .language: [Color(red: 0.25, green: 0.8, blue: 0.84), Color(red: 0.05, green: 0.56, blue: 0.68)]
        case .about: [Color(red: 0.38, green: 0.55, blue: 1), Color(red: 0.24, green: 0.25, blue: 0.86)]
        }
    }
}

extension ToolId {
    /// The pane that shows the tool, whose icon stands for it.
    var pane: SettingsPane {
        switch self {
        case .appSwitcher: .switcher
        case .layoutSwitcher: .language
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
                Section(ToolId.appSwitcher.name) {
                    ForEach([SettingsPane.switcher, .keys, .monitors, .exclusions]) { pane in
                        row(pane)
                    }
                }
                Section(ToolId.layoutSwitcher.name) {
                    row(.language)
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
                case .general: GeneralPane(model: model)
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
        return enabled.allSatisfy({ model.state(of: $0) == .running }) ? ("Active", .green) : ("Starting", .orange)
    }
}

/// A tool's state as a dot and a word, as the Tools card and the panes show it.
struct ToolStatusLabel: View {
    let state: ToolState
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: color)
                .scaleEffect(0.8)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private var text: String {
        switch state {
        case .running: "Running"
        case .starting: isEnabled ? "Starting" : "Off"
        case .failed: "Failed"
        case .off: isEnabled ? "Starting" : "Off"
        }
    }

    private var color: Color {
        switch state {
        case .running: .green
        case .failed: .red
        case .starting, .off: isEnabled ? .orange : Color(white: 0.6)
        }
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
