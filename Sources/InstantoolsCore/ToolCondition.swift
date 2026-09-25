/// How a tool is doing, as Settings and the menu show it.
public enum ToolCondition: Equatable, Sendable {
    case off
    case starting
    /// Running and doing its job.
    case active
    /// Running without doing its job: macOS kept Cmd+Tab, or Language cannot see keys.
    case inactive
    case failed(String)

    public init(enabled: Bool, state: ToolState, isActive: Bool) {
        if case .failed(let reason) = state {
            self = .failed(reason)
        } else if !enabled {
            self = .off
        } else if state == .running {
            self = isActive ? .active : .inactive
        } else {
            self = .starting
        }
    }

    /// Whether a running tool does its job, going by its latest status. The Language tool leaves the Input
    /// Monitoring check out of its status, since the check takes about 10 ms on its run loop, so the caller
    /// makes it, and it is made only when it decides the answer.
    public static func isActive(
        _ tool: ToolId, state: ToolState, handlesCmdTab: Bool?, tapRunning: Bool?, inputMonitoring: () -> Bool
    ) -> Bool {
        guard state == .running else { return false }
        return switch tool {
        case .appSwitcher: handlesCmdTab != false
        case .layoutSwitcher: tapRunning != false && inputMonitoring()
        }
    }
}
