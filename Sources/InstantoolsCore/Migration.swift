/// What the first launch takes over from InstantTab and InstantLang, the apps Instantools replaces. The old
/// apps and their config stay where they are, so going back is always possible.
public enum Migration {
    public enum OldApp: String, CaseIterable, Sendable {
        case instantTab = "InstantTab"
        case instantLang = "InstantLang"

        public var bundleId: String { "com.infeace.\(rawValue)" }
        /// Also the label of its login agent.
        public var agentLabel: String { bundleId }
        public var tool: ToolId {
            switch self {
            case .instantTab: .appSwitcher
            case .instantLang: .layoutSwitcher
            }
        }
    }

    public struct Facts: Equatable, Sendable {
        public var newConfigExists: Bool
        public var oldConfigExists: Bool
        /// Apps whose login agent plist exists, or was removed by the install script.
        public var loginAgents: Set<OldApp>
        /// In ~/Applications.
        public var installed: Set<OldApp>
        public var running: Set<OldApp>

        public init(
            newConfigExists: Bool = false, oldConfigExists: Bool = false, loginAgents: Set<OldApp> = [],
            installed: Set<OldApp> = [], running: Set<OldApp> = []
        ) {
            self.newConfigExists = newConfigExists
            self.oldConfigExists = oldConfigExists
            self.loginAgents = loginAgents
            self.installed = installed
            self.running = running
        }
    }

    public struct Plan: Equatable, Sendable {
        /// Copied, never moved, so the old app keeps its settings.
        public var copyOldConfig: Bool
        /// Booted out and their plists removed, since at login they would fight Instantools for the same keys.
        public var agentsToRemove: [OldApp]
        public var enableStartAtLogin: Bool
        public var enabledTools: Set<ToolId>
        /// On a fresh install nothing is enabled, so Settings opens to let the user choose.
        public var showSettings: Bool
    }

    public static func plan(for facts: Facts) -> Plan {
        var used = facts.installed.union(facts.running).union(facts.loginAgents)
        if facts.oldConfigExists { used.insert(.instantTab) }
        let enabled = Set(used.map(\.tool))
        return Plan(
            copyOldConfig: facts.oldConfigExists && !facts.newConfigExists,
            agentsToRemove: OldApp.allCases.filter(facts.loginAgents.contains),
            enableStartAtLogin: !facts.loginAgents.isEmpty,
            enabledTools: enabled,
            showSettings: enabled.isEmpty
        )
    }
}
