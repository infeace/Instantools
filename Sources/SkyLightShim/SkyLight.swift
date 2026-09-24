import ApplicationServices
import Darwin

/// Private SkyLight entry points, resolved at runtime so a missing symbol degrades to nil
/// instead of failing at launch. This is the only module that may touch private APIs.
public enum SkyLight {
    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    public static var isAvailable: Bool { handle != nil }

    /// Looks in SkyLight first, then in every image already loaded (for HIServices symbols).
    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let pointer = handle.flatMap({ dlsym($0, name) }) ?? dlsym(defaultHandle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}

/// Native hotkeys matched by WindowServer before any app sees them.
public enum SymbolicHotKey: UInt32, CaseIterable, Sendable {
    case commandTab = 1
    case commandShiftTab = 2
}

extension SkyLight {
    private typealias SetSymbolicHotKeyEnabled = @convention(c) (UInt32, Bool) -> CGError
    private typealias IsSymbolicHotKeyEnabled = @convention(c) (UInt32) -> Bool

    private static let setSymbolicHotKeyEnabled =
        symbol("CGSSetSymbolicHotKeyEnabled", as: SetSymbolicHotKeyEnabled.self)
    private static let isSymbolicHotKeyEnabled =
        symbol("CGSIsSymbolicHotKeyEnabled", as: IsSymbolicHotKeyEnabled.self)

    /// The change outlives this process, so callers must restore it on every exit path.
    @discardableResult
    public static func setEnabled(_ enabled: Bool, _ hotKey: SymbolicHotKey) -> Bool {
        guard let setSymbolicHotKeyEnabled else { return false }
        return setSymbolicHotKeyEnabled(hotKey.rawValue, enabled) == .success
    }

    public static func isEnabled(_ hotKey: SymbolicHotKey) -> Bool? {
        isSymbolicHotKeyEnabled?(hotKey.rawValue)
    }
}
