import InstantoolsCore
import InstantoolsKit
import SwiftUI
import WindowSnapperCore

struct SnappingPane: View {
    let model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        let status = status
        let enabled = model.isEnabled(.windowSnapper)
        PaneScroll { _ in
            PaneHeader(pane: .snapping, subtitle: "Snap windows into place with a shortcut, or by dragging them to an edge of the screen.")
            FileProblemBanner(configStore: model.snapStore)
            Hero {
                DragPicture(isActive: model.isActive(.windowSnapper))
            } bar: {
                ToolStatusBar(model: model, tool: .windowSnapper, status: status, toggleLabel: "Use InstantSnap")
            }
            if enabled, !model.accessibilityGranted {
                Callout(
                    permission: .accessibility,
                    title: "Allow Accessibility access",
                    message: "InstantSnap needs it to move and resize other apps' windows."
                )
            }
            if enabled, model.rectangleIsRunning {
                Callout(
                    symbol: "exclamationmark.triangle.fill", colors: [.orange, Color(red: 0.93, green: 0.42, blue: 0.1)],
                    title: "Rectangle is running",
                    message: "Both would move windows on the same shortcuts and drags. Quit it, and turn off Launch on login in its settings.",
                    action: "Quit Rectangle", perform: model.quitRectangle
                )
            }
            if enabled, model.snapStore.config.dragToSnap, model.macTilingIsOn {
                Callout(
                    symbol: Tile.snapping.symbol, colors: Tile.snapping.colors,
                    title: "Turn off macOS window tiling",
                    message: "Its own drag to the edges fights InstantSnap's. In Desktop & Dock, turn off Drag windows to screen edges to tile and Drag windows to menu bar to fill screen.",
                    action: "Open Desktop & Dock…", prominent: false, perform: SnapSystem.openDesktopSettings
                )
            }
            Group {
                dragging
                windows
            }
            .disabled(model.snapStore.fileIsBroken)
            configuration
        }
    }

    private var status: (title: String, subtitle: String, color: Color) {
        guard model.isEnabled(.windowSnapper) else {
            return ("Off", "Shortcuts and drags leave windows alone for now.", .orange)
        }
        let taken = model.unavailableSnapShortcuts.count
        switch model.state(of: .windowSnapper) {
        case .failed(let reason):
            return ("InstantSnap stopped", reason, .red)
        case .running where !model.isActive(.windowSnapper):
            return ("Waiting for permission", "Allow Accessibility so InstantSnap can move windows.", .orange)
        case .running where taken > 0:
            let shortcuts = taken == 1 ? "1 shortcut" : "\(taken) shortcuts"
            return ("Another app has \(shortcuts)", "They are marked under Shortcuts. The others work.", .orange)
        case .running:
            let subtitle = model.snapStore.config.dragToSnap
                ? "Press a shortcut, or drag a window to an edge of the screen."
                : "Press a shortcut to snap the front window."
            return ("InstantSnap moves your windows", subtitle, .green)
        case .starting, .off:
            return ("Starting", "Shortcuts and drags work once it is ready.", .orange)
        }
    }

    private var dragging: some View {
        SettingsCard(
            title: "Dragging",
            footer: "Left and right edges take halves, the top fills the screen, the bottom takes a third and the corners take quarters. Portrait monitors take halves at the top and bottom and thirds at the sides. Drag a snapped window away to get its old size back."
        ) {
            SettingsRow(title: "Snap by dragging to an edge", subtitle: "Drag a window by its title bar to an edge or a corner. A preview shows where it will land.") {
                Toggle("Snap by dragging to an edge", isOn: model.snapBinding(\.dragToSnap))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var windows: some View {
        SettingsCard(title: "Windows") {
            SettingsRow(title: "Gaps", subtitle: "Space between snapped windows, and between them and the edges of the screen.") {
                ValueSlider(label: "Gaps", value: gap, range: 0...Double(SnapConfig.maxGap), step: 2, unit: "pt")
            }
            RowDivider()
            SettingsRow(title: "Pressing a half again", subtitle: repeatSubtitle) {
                Picker("Pressing a half again", selection: model.snapBinding(\.repeatMode)) {
                    Text("Next monitor").tag(RepeatMode.nextDisplay)
                    Text("Resizes").tag(RepeatMode.cycleSizes)
                    Text("Nothing").tag(RepeatMode.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var repeatSubtitle: String {
        switch model.snapStore.config.repeatMode {
        case .nextDisplay: "Left or right again moves the window on to the next monitor that way."
        case .cycleSizes: "Goes from a half to two thirds, then one third, then back."
        case .none: "The window stays where the first press put it."
        }
    }

    private var configuration: some View {
        SettingsCard(title: "Configuration") {
            SettingsRow(title: "Settings file", subtitle: "\(ConfigFileStore<SnapConfig>.fileURL.abbreviatedPath), kept in sync with this window.") {
                HStack(spacing: 8) {
                    Button("Show in Finder") { model.snapStore.revealInFinder() }
                    Button("Open") { model.snapStore.openInEditor() }
                }
                .glassButton()
            }
            ForEach(Array(model.snapStore.warnings.enumerated()), id: \.offset) { _, warning in
                RowDivider()
                MessageRow(text: warning, isError: false)
            }
            if model.rectangleSettingsToImport != nil {
                RowDivider()
                SettingsRow(title: "Rectangle's settings", subtitle: "Take its shortcuts, gaps and what pressing a half again does.") {
                    Button("Import") { model.importRectangle() }
                        .glassButton()
                        .disabled(model.snapStore.fileIsBroken)
                }
            }
            RowDivider()
            SettingsRow(title: "Reset InstantSnap settings", subtitle: "Back to defaults, including every shortcut.") {
                Button("Reset…", role: .destructive) { confirmingReset = true }
                    .glassButton()
            }
        }
        .confirmationDialog("Reset InstantSnap settings?", isPresented: $confirmingReset) {
            Button("Reset InstantSnap Settings", role: .destructive) { model.snapStore.resetToDefaults() }
        } message: {
            Text("Every shortcut goes back to its default too. This cannot be undone.")
        }
    }

    private var gap: Binding<Double> {
        let gap = model.snapBinding(\.gap)
        return Binding(get: { Double(gap.wrappedValue) }, set: { gap.wrappedValue = Int($0) })
    }
}

/// A window dragged to the left edge of a monitor, with the preview of the half it will take.
private struct DragPicture: View {
    let isActive: Bool
    @Environment(\.compactLayout) private var compact

    var body: some View {
        let width: CGFloat = compact ? 240 : 290
        let height = (width * 0.56).rounded()
        let screen = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                screen.fill(.black.opacity(0.3))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: width / 2 - 9, height: height - 12)
                    .offset(x: 6, y: 6)
                MiniWindow()
                    .frame(width: width * 0.44, height: height * 0.5)
                    .offset(x: width * 0.06, y: height * 0.27)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: 1, y: height * 0.29)
            }
            .frame(width: width, height: height)
            .clipShape(screen)
            .overlay(screen.strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                .fill(.white.opacity(0.35))
                .frame(width: width * 0.22, height: 10)
        }
        .opacity(isActive ? 1 : 0.55)
        .saturation(isActive ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel("A window dragged to the left edge of the screen, with a preview of the left half it will take")
    }
}

private struct MiniWindow: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.9)).frame(width: 5, height: 5)
                }
            }
            .padding(5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.97)))
        .overlay(shape.strokeBorder(.black.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}
