import Foundation

public struct Config: Sendable, Equatable {
    public enum Scope: String, Sendable, CaseIterable {
        case all
        case mouseDisplay
    }

    public enum Placement: String, Sendable, CaseIterable {
        case show
        case end
        case hide
    }

    public struct Exclusion: Sendable, Equatable {
        public enum When: String, Sendable, CaseIterable {
            case always
            case noWindows
        }

        /// An exact bundle id, or a prefix when it ends with `*`.
        public var bundleId: String
        public var when: When

        public init(bundleId: String, when: When = .always) {
            self.bundleId = bundleId
            self.when = when
        }

        /// Bundle ids are case-insensitive on macOS.
        func matches(_ candidate: String) -> Bool {
            let pattern = bundleId.lowercased()
            let candidate = candidate.lowercased()
            return pattern.hasSuffix("*") ? candidate.hasPrefix(pattern.dropLast()) : candidate == pattern
        }
    }

    public var showDelayMs = 50
    public var scope = Scope.all
    public var windowlessApps = Placement.show
    public var iconSize = 96.0
    public var exclude: [Exclusion] = []

    public init() {}

    public func isExcluded(bundleId: String?, hasWindows: Bool) -> Bool {
        guard let bundleId else { return false }
        return exclude.contains { rule in
            rule.matches(bundleId) && (rule.when == .always || !hasWindows)
        }
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case syntax(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .syntax(let message): "syntax error: \(message)"
        case .invalid(let message): message
        }
    }
}

extension Config {
    public struct Parsed: Sendable, Equatable {
        public var config: Config
        public var warnings: [String]
    }

    private static let knownKeys: Set = ["showDelayMs", "scope", "windowlessApps", "iconSize", "exclude"]
    private static let knownExclusionKeys: Set = ["bundleId", "when"]

    /// Parses JSON5 (comments, trailing commas and unquoted keys allowed). Missing keys keep their
    /// defaults, unknown keys are reported as warnings, invalid values are errors.
    public static func parse(_ data: Data) throws(ConfigError) -> Parsed {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
        } catch {
            let nsError = error as NSError
            throw .syntax(nsError.userInfo[NSDebugDescriptionErrorKey] as? String ?? nsError.localizedDescription)
        }
        guard let root = object as? [String: Any] else { throw .invalid("the config must be an object") }

        var config = Config()
        var warnings = root.keys.sorted().filter { !knownKeys.contains($0) }.map { "unknown key '\($0)' ignored" }

        if let value = root["showDelayMs"] {
            guard !isBoolean(value), let number = value as? Int, (0...1000).contains(number) else {
                throw .invalid("showDelayMs must be a whole number from 0 to 1000")
            }
            config.showDelayMs = number
        }
        if let value = root["scope"] {
            config.scope = try enumValue("scope", value)
        }
        if let value = root["windowlessApps"] {
            config.windowlessApps = try enumValue("windowlessApps", value)
        }
        if let value = root["iconSize"] {
            guard !isBoolean(value), let number = value as? Double, (32...256).contains(number) else {
                throw .invalid("iconSize must be a number from 32 to 256")
            }
            config.iconSize = number
        }
        if let value = root["exclude"] {
            guard let rules = value as? [Any] else { throw .invalid("exclude must be a list") }
            for (index, rule) in rules.enumerated() {
                config.exclude.append(try exclusion(rule, index: index, warnings: &warnings))
            }
        }
        return Parsed(config: config, warnings: warnings)
    }

    private static func exclusion(_ value: Any, index: Int, warnings: inout [String]) throws(ConfigError) -> Exclusion {
        if let bundleId = value as? String, !bundleId.isEmpty {
            return Exclusion(bundleId: bundleId)
        }
        guard let rule = value as? [String: Any] else {
            throw .invalid("exclude[\(index)] must be a bundle id or an object with bundleId")
        }
        warnings += rule.keys.sorted().filter { !knownExclusionKeys.contains($0) }
            .map { "unknown key 'exclude[\(index)].\($0)' ignored" }
        guard let bundleId = rule["bundleId"] as? String, !bundleId.isEmpty else {
            throw .invalid("exclude[\(index)].bundleId must be a non-empty string")
        }
        var when = Exclusion.When.always
        if let value = rule["when"] {
            when = try enumValue("exclude[\(index)].when", value)
        }
        return Exclusion(bundleId: bundleId, when: when)
    }

    /// JSON booleans bridge to NSNumber and would otherwise pass as 0 or 1.
    private static func isBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    private static func enumValue<Value: RawRepresentable & CaseIterable>(
        _ key: String, _ value: Any
    ) throws(ConfigError) -> Value where Value.RawValue == String {
        guard let raw = value as? String, let parsed = Value(rawValue: raw) else {
            let allowed = Value.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            throw .invalid("\(key) must be one of \(allowed)")
        }
        return parsed
    }
}

extension Config {
    /// Written on first launch. Parses to the defaults, so it doubles as documentation.
    public static let defaultFileContents = """
    // InstantTab settings. Changes apply as soon as you save this file.
    {
      // Milliseconds before the switcher is drawn. A Cmd+Tab released sooner
      // switches without drawing anything. 0 draws immediately.
      showDelayMs: 50,

      // Which apps to list:
      //   "all"           every running app, like native Cmd+Tab
      //   "mouseDisplay"  only apps with a window on the display under the mouse
      scope: "all",

      // Apps with no visible window (hidden, minimized or windowless):
      //   "show" in recent order, "end" after the others, or "hide".
      windowlessApps: "show",

      // Icon size in points. Shrinks automatically when the apps do not fit.
      iconSize: 96,

      // Apps to leave out, by bundle id. A trailing * matches a prefix.
      // "when" is "always" (the default) or "noWindows".
      exclude: [
        // "com.example.App",
        // { bundleId: "com.apple.finder", when: "noWindows" },
      ],
    }

    """
}
