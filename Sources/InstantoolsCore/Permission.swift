/// What a tool asks macOS for. Tools run as part of the host, so macOS asks once and lists only the host.
public enum Permission: Sendable {
    case accessibility
    case inputMonitoring

    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }
}

/// The host's two checks. The Input Monitoring one also passes with Accessibility alone, and fails with
/// Accessibility on only once Input Monitoring was switched off.
public struct PermissionState: Equatable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool

    public init(accessibility: Bool, inputMonitoring: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    /// Without Accessibility a failing check cannot be told from never asked.
    public var inputMonitoringSwitchedOff: Bool {
        accessibility && !inputMonitoring
    }

    public func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }

    /// What a tool that is on lacks right now. Cmd+Tab asks for Input Monitoring only once it was switched
    /// off, since Accessibility covers it otherwise.
    public func missing(for tool: ToolId) -> [Permission] {
        switch tool {
        case .appSwitcher: (accessibility ? [] : [.accessibility]) + (inputMonitoringSwitchedOff ? [.inputMonitoring] : [])
        case .layoutSwitcher: inputMonitoring ? [] : [.inputMonitoring]
        }
    }

    /// What tools being set up need, granted or not, so each can show its status. Input Monitoring is left out
    /// once Accessibility covers it, and explained by Language, which needs it most.
    public func needed(by tools: Set<ToolId>) -> [PermissionNeed] {
        var needs: [PermissionNeed] = []
        if tools.contains(.appSwitcher) { needs.append(PermissionNeed(.accessibility, for: .appSwitcher)) }
        if tools.contains(.layoutSwitcher), !(accessibility && inputMonitoring) {
            needs.append(PermissionNeed(.inputMonitoring, for: .layoutSwitcher))
        } else if tools.contains(.appSwitcher), inputMonitoringSwitchedOff {
            needs.append(PermissionNeed(.inputMonitoring, for: .appSwitcher))
        }
        return needs
    }
}

public struct PermissionNeed: Equatable, Sendable {
    public var permission: Permission
    /// The tool whose reason is shown.
    public var tool: ToolId

    public init(_ permission: Permission, for tool: ToolId) {
        self.permission = permission
        self.tool = tool
    }
}
