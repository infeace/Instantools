import InstantTabCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
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
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch selection ?? .general {
            case .general: GeneralPane(model: model)
            }
        }
    }
}

/// A slider with its current value shown to the right.
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            // Rounded here rather than with `step:`, which draws a tick mark per step.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .frame(minWidth: 160, maxWidth: 240)
            Text("\(Int(value)) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
