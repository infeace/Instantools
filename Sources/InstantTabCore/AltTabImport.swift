import Foundation

/// Reads AltTab's `exceptions` preference, a JSON list of per-app rules.
public enum AltTabImport {
    /// Only rules that hide an app from the switcher are imported. AltTab's `hide` is "1" for always and
    /// "2" for when the app has no open window; `ignore` (shortcuts off in fullscreen) has no equivalent.
    public static func exclusions(fromExceptionsJSON json: String) -> [Config.Exclusion] {
        guard let data = json.data(using: .utf8),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return rules.compactMap { rule in
            guard let bundleId = rule["bundleIdentifier"] as? String, !bundleId.isEmpty else { return nil }
            switch rule["hide"] as? String {
            case "1": return Config.Exclusion(bundleId: bundleId, when: .always)
            case "2": return Config.Exclusion(bundleId: bundleId, when: .noWindows)
            default: return nil
            }
        }
    }
}

extension Config {
    /// Adds rules for apps not already excluded, keeping existing rules as they are.
    public mutating func addExclusions(_ rules: [Exclusion]) {
        for rule in rules where !exclude.contains(where: { $0.bundleId.lowercased() == rule.bundleId.lowercased() }) {
            exclude.append(rule)
        }
    }
}
