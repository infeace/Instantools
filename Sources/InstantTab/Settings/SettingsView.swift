import InstantTabCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case monitors
    case exclusions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .monitors: "Monitors"
        case .exclusions: "Excluded Apps"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .monitors: "display.2"
        case .exclusions: "eye.slash.fill"
        case .about: "info"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: [Color(white: 0.62), Color(white: 0.45)]
        case .monitors: [Color(red: 0.33, green: 0.62, blue: 1), Color(red: 0.13, green: 0.42, blue: 0.93)]
        case .exclusions: [Color(red: 1, green: 0.42, blue: 0.45), Color(red: 0.88, green: 0.2, blue: 0.33)]
        case .about: [Color(red: 0.38, green: 0.55, blue: 1), Color(red: 0.24, green: 0.25, blue: 0.86)]
        }
    }
}

struct SettingsView: View {
    let model: SettingsModel
    @State private var selection: SettingsPane?

    init(model: SettingsModel, initialPane: SettingsPane = .general) {
        self.model = model
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SettingsPane.allCases.filter { $0 != .about }) { pane in
                        row(pane)
                    }
                }
                Section {
                    row(.about)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SidebarHeader(model: model)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch selection ?? .general {
            case .general: GeneralPane(model: model)
            case .monitors: MonitorsPane(model: model)
            case .exclusions: ExclusionsPane(model: model)
            case .about: AboutPane(model: model)
            }
        }
        .toolbar(removing: .sidebarToggle)
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
                Text("InstantTab")
                    .font(.headline)
                HStack(spacing: 5) {
                    StatusDot(color: model.isPaused ? .orange : .green)
                        .scaleEffect(0.8)
                    Text(model.isPaused ? "Paused" : "Active")
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
}

struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            // Rounded here because `step:` draws a tick mark per step.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .frame(minWidth: 150, maxWidth: 210)
            Text(verbatim: "\(Int(value)) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
