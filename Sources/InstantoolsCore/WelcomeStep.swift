/// The first launch's steps. Choosing no tool skips the permissions, since nothing needs them.
public enum WelcomeStep: String, CaseIterable, Sendable {
    case tools
    case permissions
    case done

    public func isSkipped(choosing tools: Set<ToolId>) -> Bool {
        self == .permissions && tools.isEmpty
    }

    public func next(choosing tools: Set<ToolId>) -> WelcomeStep? {
        Self.allCases.drop { $0 != self }.dropFirst().first { !$0.isSkipped(choosing: tools) }
    }

    public func previous(choosing tools: Set<ToolId>) -> WelcomeStep? {
        Self.allCases.reversed().drop { $0 != self }.dropFirst().first { !$0.isSkipped(choosing: tools) }
    }
}
