import AppKit
import WindowSnapperCore

/// What InstantSnap's Settings reads from the rest of the Mac: macOS's own window tiling, and Rectangle.
@MainActor
enum SnapSystem {
    private static let windowManager = "com.apple.WindowManager" as CFString

    /// macOS's own drag to the edges, which fights InstantSnap's. Both switches are on unless turned off, from
    /// macOS 15, which brought them.
    static var macTilingIsOn: Bool {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) else {
            return false
        }
        CFPreferencesAppSynchronize(windowManager)
        return ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"].contains { key in
            (CFPreferencesCopyAppValue(key as CFString, windowManager) as? Bool) ?? true
        }
    }

    static func openDesktopSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static var rectangleIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: RectangleImport.bundleId).isEmpty
    }

    static func quitRectangle() {
        NSRunningApplication.runningApplications(withBundleIdentifier: RectangleImport.bundleId).forEach { $0.terminate() }
    }

    /// Only Rectangle's own domain. UserDefaults(suiteName:) would mix in the global one.
    private static func rectangleDefaults() -> [String: Any] {
        let domain = RectangleImport.bundleId as CFString
        guard let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
              let values = CFPreferencesCopyMultiple(keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
        else { return [:] }
        return values
    }

    /// Rectangle's settings as InstantSnap's, nil when Rectangle has none.
    static func rectangleConfig() -> SnapConfig? {
        let defaults = rectangleDefaults()
        return RectangleImport.hasSettings(defaults) ? RectangleImport.config(from: defaults) : nil
    }

    /// What snap.json5 starts as: Rectangle's settings when it has any, so its users keep their keys.
    static func initialConfig() -> SnapConfig {
        rectangleConfig() ?? SnapConfig()
    }
}
