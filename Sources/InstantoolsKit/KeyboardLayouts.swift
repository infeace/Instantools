import Carbon
import Foundation

/// The keyboard layouts and input method modes that can be selected, for the Language tool and for Settings in
/// the host. Text Input Sources is not thread safe, so all of it runs on the main thread.
@MainActor
public enum KeyboardLayouts {
    @MainActor
    public struct Layout {
        public let id: String
        public let source: TISInputSource

        public var name: String {
            KeyboardLayouts.string(source, kTISPropertyLocalizedName) ?? id
        }

        /// Input modes usually have one. Keyboard layouts have only an IconRef, and NSImage's init for those is
        /// deprecated.
        public var iconURL: URL? {
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) else { return nil }
            return Unmanaged<CFURL>.fromOpaque(raw).takeUnretainedValue() as URL
        }

        /// The main language it types, such as "en" or "bg".
        public var language: String? {
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return nil }
            return (Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String])?.first
        }
    }

    /// Only layouts and input method modes, so a switch never lands on Emoji & Symbols or Dictation.
    public static func enabled() -> [Layout] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        let types: Set<String> = [kTISTypeKeyboardLayout as String, kTISTypeKeyboardInputMode as String]
        return sources
            .filter { string($0, kTISPropertyInputSourceType).map(types.contains) ?? false }
            .map { Layout(id: id(of: $0), source: $0) }
    }

    public static func currentId() -> String {
        id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    public static func id(of source: TISInputSource) -> String {
        string(source, kTISPropertyInputSourceID) ?? ""
    }

    public static func select(_ source: TISInputSource) -> OSStatus {
        TISSelectInputSource(source)
    }

    /// Delivered at once: by default distributed notifications wait while the app is inactive, and an accessory
    /// app never becomes active.
    public static func observeChanges(_ observer: NSObject, enabled: Selector, selected: Selector) {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            observer, selector: enabled, name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            observer, selector: selected, name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    fileprivate static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
