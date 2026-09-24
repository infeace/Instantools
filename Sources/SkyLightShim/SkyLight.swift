import ApplicationServices
import Darwin

/// The only module that touches private APIs. Symbols resolve at runtime, so a missing one degrades to
/// nil instead of failing at launch.
public enum SkyLight {
    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let pointer = handle.flatMap({ dlsym($0, name) }) ?? dlsym(defaultHandle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}

public enum SymbolicHotKey: UInt32, CaseIterable, Sendable {
    case commandTab = 1
    case commandShiftTab = 2
}

extension SkyLight {
    private typealias SetSymbolicHotKeyEnabled = @convention(c) (UInt32, Bool) -> CGError

    private static let setSymbolicHotKeyEnabled =
        symbol("CGSSetSymbolicHotKeyEnabled", as: SetSymbolicHotKeyEnabled.self)

    @discardableResult
    public static func setEnabled(_ enabled: Bool, _ hotKey: SymbolicHotKey) -> Bool {
        guard let setSymbolicHotKeyEnabled else { return false }
        return setSymbolicHotKeyEnabled(hotKey.rawValue, enabled) == .success
    }
}
