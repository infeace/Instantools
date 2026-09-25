/// Every tool Instantools runs. Each runs in its own process, started and supervised by the host.
public enum ToolId: String, CaseIterable, Codable, Sendable, Identifiable {
    case appSwitcher
    case layoutSwitcher

    public var id: Self { self }

    public var name: String {
        switch self {
        case .appSwitcher: "Cmd+Tab"
        case .layoutSwitcher: "Language"
        }
    }

    public var summary: String {
        switch self {
        case .appSwitcher: "An app switcher that appears the moment you press Cmd+Tab."
        case .layoutSwitcher: "Control+Command switches the keyboard layout, pressed in either order."
        }
    }

    /// Its file in Contents/Helpers. Leftover copies from a crash or an old install are found by it too.
    public var executableName: String {
        switch self {
        case .appSwitcher: "InstantoolsAppSwitcher"
        case .layoutSwitcher: "InstantoolsLayoutSwitcher"
        }
    }
}

public enum ToolLaunch {
    /// Set by the host on every tool it starts. A tool started any other way would be its own app to macOS,
    /// without the host's permissions, and could run beside the host's copy.
    public static let environmentKey = "INSTANTOOLS_TOOL"
    /// "0" when the Cmd+Tab tool will ask for Accessibility, which covers listening, so one prompt is enough.
    public static let askInputMonitoringKey = "INSTANTOOLS_ASK_INPUT_MONITORING"
    /// Seconds a tool keeps working once the host is gone, so Cmd+Tab and layout switching survive a host crash
    /// while launchd relaunches it, without leaving tools running forever after a force quit.
    public static let hostGoneGrace = 15.0
    /// Seconds between asking a tool to stop and killing it.
    public static let stopTimeout = 2.0
}

public enum ToolState: Equatable, Sendable {
    case off
    case starting
    case running
    case failed(String)
}
