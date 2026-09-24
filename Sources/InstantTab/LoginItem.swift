import AppKit
import ServiceManagement

/// Start at login through a LaunchAgent in ~/Library/LaunchAgents. Toggling only writes or removes the
/// file, so it takes effect instantly and never restarts the running copy; launchd picks the agent up
/// at the next login and then relaunches InstantTab if it ever crashes, so native Cmd+Tab is never left
/// off. A classic agent is used rather than SMAppService: without a Team ID, macOS pins an SMAppService
/// agent to the exact binary that registered it, and every rebuild then fails its launch constraint.
@MainActor
enum LoginItem {
    static let label = "com.infeace.InstantTab"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(label).plist")
    }

    /// Whether this copy was started by the login agent.
    nonisolated static var isSupervised: Bool {
        ProcessInfo.processInfo.environment["INSTANTTAB_LAUNCH_AGENT"] == "1"
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Classic agents need no approval, though macOS can still switch them off in Login Items.
    static var needsApproval: Bool { false }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try write()
        } else if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func openSettings() {
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
