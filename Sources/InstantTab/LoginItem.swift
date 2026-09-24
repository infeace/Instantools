import Foundation
import ServiceManagement

/// A classic LaunchAgent, toggled by writing or removing its file. SMAppService is avoided because without
/// a Team ID macOS pins its agent to the exact binary that registered it, so every rebuild breaks it.
@MainActor
enum LoginItem {
    static let label = "com.infeace.InstantTab"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(label).plist")
    }

    nonisolated static var isSupervised: Bool {
        ProcessInfo.processInfo.environment["INSTANTTAB_LAUNCH_AGENT"] == "1"
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// On here, but switched off in System Settings > Login Items.
    static var isBlockedInLoginItems: Bool {
        isEnabled && SMAppService.statusForLegacyPlist(at: plistURL) == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try write()
        } else if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func repairIfMoved() {
        guard isEnabled,
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let recorded = (plist["ProgramArguments"] as? [String])?.first,
              !FileManager.default.fileExists(atPath: recorded)
        else { return }
        try? write()
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func write() throws {
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "EnvironmentVariables": ["INSTANTTAB_LAUNCH_AGENT": "1"],
            "RunAtLoad": true,
            // Relaunch after a crash, not after quitting.
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
    }
}
