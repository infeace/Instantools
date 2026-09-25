import AppKit
import AppSwitcherCore
import SwiftUI

struct AppKeysPane: View {
    let model: SettingsModel
    @State private var recording: Recording?
    @State private var problem: String?

    /// The key being set, for a binding that exists or for an app just picked.
    private enum Recording: Equatable {
        case change(Character)
        case add(bundleId: String)
    }

    private var bindings: [Config.AppKey] { model.configStore.config.appKeys }

    var body: some View {
        PaneScroll { _ in
            PaneHeader(pane: .keys, subtitle: "Hold Cmd, press Tab, then an app's key to go straight to it. An app that is not running opens.")
            FileProblemBanner(configStore: model.configStore)
            SettingsCard(
                title: "App keys",
                footer: "Keys follow your keyboard layout. On a layout without Latin letters, such as Cyrillic, a key counts as the letter in its place on a US keyboard."
            ) {
                if bindings.isEmpty && recording == nil {
                    EmptyRow(text: "No app keys yet. Add an app, then press the key to use for it.")
                }
                DividedRows(bindings, id: \.key) { binding in
                    row(bundleId: binding.bundleId, key: binding.key, recordingAs: .change(binding.key)) {
                        model.removeAppKey(binding.key)
                    }
                }
                if case .add(let bundleId) = recording {
                    if !bindings.isEmpty { RowDivider(indented: true) }
                    row(bundleId: bundleId, key: nil, recordingAs: .add(bundleId: bundleId), remove: stopRecording)
                }
                CardActions { addButtons }
            }
            .disabled(model.configStore.fileIsBroken)
        }
        .background(KeyCapture(isActive: recording != nil && !model.configStore.fileIsBroken, onKey: handle))
        // A recorder left armed for a row that is gone would swallow keys with nothing on screen.
        .onChange(of: bindings.map(\.key)) {
            if case .change(let key) = recording, !bindings.contains(where: { $0.key == key }) { stopRecording() }
        }
        .onDisappear(perform: stopRecording)
    }

    private func row(bundleId: String, key: Character?, recordingAs state: Recording, remove: @escaping () -> Void) -> some View {
        let info = model.apps.info(for: bundleId)
        let isRecording = recording == state
        let subtitle = isRecording
            ? problem ?? "Press a letter or digit. Esc cancels."
            : info.subtitle(bundleId: bundleId)
        return AppKeyRow(
            info: info, subtitle: subtitle, isProblem: isRecording && problem != nil, key: key, isRecording: isRecording,
            record: { toggle(state) }, remove: remove
        )
    }

    @ViewBuilder private var addButtons: some View {
        RunningAppMenu(apps: model.runningApps) { toggle(.add(bundleId: $0)) }
        Button("Choose App…") {
            if let bundleId = model.chooseApps(title: "Choose an app", prompt: "Choose", multiple: false).first {
                toggle(.add(bundleId: bundleId))
            }
        }
    }

    private func toggle(_ state: Recording) {
        recording = recording == state ? nil : state
        problem = nil
    }

    private func stopRecording() {
        recording = nil
        problem = nil
    }

    private func handle(_ event: NSEvent) {
        guard let recording else { return }
        guard Int64(event.keyCode) != KeyCode.escape else { return stopRecording() }
        // With Cmd, as the switcher reads it, since layouts such as Dvorak - QWERTY ⌘ change with Cmd held.
        let key = SessionKey.character(keycode: Int64(event.keyCode), characters: event.characters(byApplyingModifiers: .command) ?? "")
        let current: Character? = if case .change(let old) = recording { old } else { nil }
        if let problem = model.configStore.config.appKeyProblem(key, replacing: current) {
            self.problem = message(for: problem, key: key)
            return
        }
        guard let key else { return }
        switch recording {
        case .change(let old):
            if let bundleId = bindings.first(where: { $0.key == old })?.bundleId {
                model.bindAppKey(key, to: bundleId, replacing: old)
            }
        case .add(let bundleId):
            model.bindAppKey(key, to: bundleId)
        }
        stopRecording()
    }

    private func message(for problem: Config.AppKeyProblem, key: Character?) -> String {
        let name = keyName(key)
        switch problem {
        case .notALetterOrDigit: return "Use a letter or a digit."
        case .reserved(let key): return "\(name) \(Config.AppKey.reservedAction(key)) the selected app, so it is taken."
        case .taken(let bundleId): return "\(name) already goes to \(model.apps.info(for: bundleId).name)."
        }
    }
}

private struct AppKeyRow: View {
    let info: AppLookup.Info
    let subtitle: String
    let isProblem: Bool
    let key: Character?
    let isRecording: Bool
    let record: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(info: info)
                .frame(width: Card.leadingWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(isProblem ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            // A keycap stays small at every width, so the row never stacks.
            Button(action: record) {
                Text(isRecording ? "Press a key…" : keyName(key))
                    .font(isRecording ? .body : .system(.body, design: .rounded).weight(.semibold))
                    .frame(minWidth: 20)
            }
            .glassButton(prominent: isRecording)
            .help(isRecording ? "Press the key to use, or Esc to cancel" : "Change the key for \(info.name)")
            .accessibilityLabel(isRecording ? "Waiting for a key for \(info.name)" : "Change key \(keyName(key)) for \(info.name)")
            RemoveButton(help: key == nil ? "Cancel adding \(info.name)" : "Remove key \(keyName(key)) for \(info.name)", action: remove)
        }
        .padding(.horizontal, Card.inset)
        .padding(.vertical, 12)
    }
}

private func keyName(_ key: Character?) -> String {
    key.map { String($0).uppercased() } ?? ""
}

/// Receives key presses while the recorder waits, and swallows them so they neither beep nor reach a control.
/// Cmd and Ctrl shortcuts, such as closing the window, still work.
private struct KeyCapture: NSViewRepresentable {
    let isActive: Bool
    let onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.setActive(isActive)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.setActive(false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var onKey: ((NSEvent) -> Void)?
        private var monitor: Any?

        func setActive(_ active: Bool) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return event }
                    self?.onKey?(event)
                    return nil
                }
            } else if !active, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
