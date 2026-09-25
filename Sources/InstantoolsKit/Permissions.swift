import AppKit
import ApplicationServices
import CoreGraphics

/// A tool started by the host counts as the host to macOS, so the host's checks answer for every tool.
public enum Permissions {
    public static var accessibility: Bool { AXIsProcessTrusted() }

    public static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static func requestAccessibilityInSettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Accessibility allows listening too, so this is only needed without it.
    public static var inputMonitoring: Bool { CGPreflightListenEventAccess() }

    public static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    public static func requestInputMonitoringInSettings() {
        requestInputMonitoring()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
