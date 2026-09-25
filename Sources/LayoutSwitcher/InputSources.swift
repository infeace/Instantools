import Carbon
import Foundation
import InstantoolsKit
import LayoutSwitcherCore

/// Keyboard layouts through Text Input Sources, which is not thread safe, so all of it runs on the main thread.
@MainActor
final class InputSources {
    private var layouts: [(id: String, source: TISInputSource)] = []
    private var history = LayoutHistory(current: InputSources.currentId())

    var names: [String] {
        layouts.map { Self.name($0.source) }
    }

    init() {
        reload()
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        center.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.history.observe(Self.currentId()) }
        }
    }

    func switchLayout() {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        history.observe(Self.id(current))
        guard let targetId = LayoutPicker.target(among: layouts.map(\.id), current: history.current, previous: history.previous),
              let target = layouts.first(where: { $0.id == targetId })?.source
        else { return }
        select(target)
    }

    /// Checked against what macOS reports straight after, with one retry, so a dropped switch is not silent.
    private func select(_ source: TISInputSource) {
        let wanted = Self.id(source)
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
        Diagnostics.log.notice("layouts: \(self.layouts.map(\.id).joined(separator: ", "), privacy: .public)")
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
