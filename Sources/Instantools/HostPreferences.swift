import Foundation
import InstantoolsCore

/// Which tools run, kept in the host's own defaults.
@MainActor
enum HostPreferences {
    private static let enabledKey = "enabledTools"

    static func isEnabled(_ tool: ToolId) -> Bool {
        enabledTools.contains(tool)
    }

    static var enabledTools: Set<ToolId> {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: enabledKey) ?? []
            return Set(raw.compactMap(ToolId.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(ToolId.allCases.filter(newValue.contains).map(\.rawValue), forKey: enabledKey)
        }
    }

    static func setEnabled(_ tool: ToolId, _ enabled: Bool) {
        if enabled { enabledTools.insert(tool) } else { enabledTools.remove(tool) }
    }
}
