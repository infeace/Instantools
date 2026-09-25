import Carbon
import Foundation
import InstantoolsKit
import LayoutSwitcherCore

/// Keyboard layouts through Text Input Sources, which is not thread safe, so all of it runs on the main thread.
@MainActor
final class InputSources: NSObject {
    private var layouts: [(id: String, source: TISInputSource)] = []
    /// The ids of `layouts`, kept so a switch builds no array.
    private var layoutIds: [String] = []
    private var history = LayoutHistory(current: InputSources.currentId())

    var names: [String] {
        layouts.map { Self.name($0.source) }
    }

    override init() {
        super.init()
        reload()
        // Delivered at once: by default distributed notifications wait while the app is inactive, and an
        // accessory tool never becomes active.
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self, selector: #selector(enabledSourcesChanged),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self, selector: #selector(selectedSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func enabledSourcesChanged() {
        reload()
    }

    @objc private func selectedSourceChanged() {
        history.observe(Self.currentId())
    }

    func switchLayout() {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        history.observe(Self.id(current))
        guard let targetId = LayoutPicker.target(among: layoutIds, current: history.current, previous: history.previous),
              let target = layouts.first(where: { $0.id == targetId })?.source
        else { return }
        select(target, id: targetId)
    }

    /// Checked against what macOS reports straight after, with one retry, so a dropped switch is not silent.
    private func select(_ source: TISInputSource, id wanted: String) {
        for attempt in 1...2 {
            let status = TISSelectInputSource(source)
            if status == noErr, Self.currentId() == wanted {
                history.observe(wanted)
                return
            }
            Diagnostics.log.error("switch to \(wanted, privacy: .public) failed on attempt \(attempt): \(status)")
        }
    }

    /// Only layouts and input method modes, so a switch never lands on Emoji & Symbols or Dictation.
    private func reload() {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        let types: Set<String> = [kTISTypeKeyboardLayout as String, kTISTypeKeyboardInputMode as String]
        layouts = sources
            .filter { Self.string($0, kTISPropertyInputSourceType).map(types.contains) ?? false }
            .map { (Self.id($0), $0) }
        layoutIds = layouts.map(\.id)
        Diagnostics.log.notice("layouts: \(self.layoutIds.joined(separator: ", "), privacy: .public)")
    }

    private static func currentId() -> String {
        id(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    private static func id(_ source: TISInputSource) -> String {
        string(source, kTISPropertyInputSourceID) ?? ""
    }

    private static func name(_ source: TISInputSource) -> String {
        string(source, kTISPropertyLocalizedName) ?? id(source)
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
