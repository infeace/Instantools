import Carbon
import Foundation
import InstantoolsKit
import LayoutSwitcherCore

/// Keyboard layouts through Text Input Sources, which is not thread safe, so all of it runs on the main thread.
@MainActor
final class InputSources: NSObject {
    private var layouts: [KeyboardLayouts.Layout] = []
    /// The ids of `layouts`, kept so a switch builds no array.
    private var layoutIds: [String] = []
    private var history = LayoutHistory(current: KeyboardLayouts.currentId())

    override init() {
        super.init()
        reload()
        KeyboardLayouts.observeChanges(self, enabled: #selector(enabledSourcesChanged), selected: #selector(selectedSourceChanged))
    }

    @objc private func enabledSourcesChanged() {
        reload()
    }

    /// Also how a layout picked from Settings or the menu becomes the one to go back from.
    @objc private func selectedSourceChanged() {
        history.observe(KeyboardLayouts.currentId())
    }

    func switchLayout() {
        history.observe(KeyboardLayouts.currentId())
        guard let targetId = LayoutPicker.target(among: layoutIds, current: history.current, previous: history.previous),
              let target = layouts.first(where: { $0.id == targetId })?.source
        else { return }
        select(target, id: targetId)
    }

    /// Checked against what macOS reports straight after, with one retry, so a dropped switch is not silent.
    private func select(_ source: TISInputSource, id wanted: String) {
        for attempt in 1...2 {
            let status = KeyboardLayouts.select(source)
            if status == noErr, KeyboardLayouts.currentId() == wanted {
                history.observe(wanted)
                return
            }
            Diagnostics.log.error("switch to \(wanted, privacy: .public) failed on attempt \(attempt): \(status)")
        }
    }

    private func reload() {
        layouts = KeyboardLayouts.enabled()
        layoutIds = layouts.map(\.id)
        Diagnostics.log.notice("layouts: \(self.layoutIds.joined(separator: ", "), privacy: .public)")
    }
}
