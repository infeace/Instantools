import Foundation

public struct Config: Sendable, Equatable {
    public enum Scope: Sendable, Hashable {
        case all
        case mouseDisplay
        case focusedDisplay
        case mouseGroup
        case group(String)

        public var rawValue: String {
            switch self {
            case .all: "all"
            case .mouseDisplay: "mouseDisplay"
            case .focusedDisplay: "focusedDisplay"
            case .mouseGroup: "mouseGroup"
            case .group(let name): "group:\(name)"
            }
        }

        public init?(rawValue: String) {
            switch rawValue {
            case "all": self = .all
            case "mouseDisplay": self = .mouseDisplay
            case "focusedDisplay": self = .focusedDisplay
            case "mouseGroup": self = .mouseGroup
            default:
                guard rawValue.hasPrefix("group:"), rawValue.count > 6 else { return nil }
                self = .group(String(rawValue.dropFirst(6)))
            }
        }
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
    }

    public var showDelayMs = 50
    public var scope = Scope.all
    public var windowlessApps = Placement.show
    public var iconSize = 96.0
    public var exclude: [Exclusion] = []
    public var displayGroups: [DisplayGroup] = []
    public var appKeys: [AppKey] = []
    /// Apps that get Cmd+Tab themselves while they are in front, such as virtual machines. Bundle id
    /// patterns like `exclude`.
    public var passThrough: [String] = []

    public init() {}

    public func excludes(_ bundleId: String) -> Bool {
        exclude.contains { $0.bundleId.caseInsensitiveCompare(bundleId) == .orderedSame }
    }

    public func passesThrough(_ bundleId: String) -> Bool {
        passThrough.contains { $0.caseInsensitiveCompare(bundleId) == .orderedSame }
    }
}

/// An exact bundle id, or a prefix when it ends with `*`. Bundle ids are case-insensitive on macOS.
public struct BundleIdPattern: Sendable {
    private let text: String
    private let isPrefix: Bool

    public init(_ pattern: String) {
        let lowercased = pattern.lowercased()
        isPrefix = lowercased.hasSuffix("*")
        text = isPrefix ? String(lowercased.dropLast()) : lowercased
    }

    /// Takes the id already lowercased, so matching one app against many patterns lowercases it once.
    func matches(lowercased id: String) -> Bool {
        isPrefix ? id.hasPrefix(text) : id == text
    }
}

/// Built once per config, so a key press only compares lowercased strings.
public struct ExclusionMatcher: Sendable {
    private let rules: [(pattern: BundleIdPattern, when: Config.Exclusion.When)]

    public init(_ exclusions: [Config.Exclusion]) {
        rules = exclusions.map { (BundleIdPattern($0.bundleId), $0.when) }
    }

    public func isExcluded(bundleId: String?, hasWindows: Bool) -> Bool {
        guard let bundleId, !rules.isEmpty else { return false }
        let id = bundleId.lowercased()
        return rules.contains { $0.pattern.matches(lowercased: id) && ($0.when == .always || !hasWindows) }
    }
}

public struct BundleIdMatcher: Sendable {
    private let patterns: [BundleIdPattern]

    public init(_ patterns: [String]) {
        self.patterns = patterns.map(BundleIdPattern.init)
    }

    public func matches(_ bundleId: String?) -> Bool {
        guard let bundleId, !patterns.isEmpty else { return false }
        let id = bundleId.lowercased()
        return patterns.contains { $0.matches(lowercased: id) }
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

    private static let knownKeys: Set = ["showDelayMs", "scope", "windowlessApps", "iconSize", "exclude", "displayGroups", "appKeys", "passThrough"]
    private static let knownExclusionKeys: Set = ["bundleId", "when"]
    private static let knownGroupKeys: Set = ["name", "match"]

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
            guard !isBoolean(value), let number = value as? Int, (0...500).contains(number) else {
                throw .invalid("showDelayMs must be a whole number from 0 to 500")
            }
            config.showDelayMs = number
        }
        if let value = root["scope"] {
            guard let raw = value as? String, let scope = Scope(rawValue: raw) else {
                throw .invalid("scope must be \"all\", \"mouseDisplay\", \"focusedDisplay\", \"mouseGroup\" or \"group:<name>\"")
            }
            config.scope = scope
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
                let parsed = try exclusion(rule, index: index, warnings: &warnings)
                guard parsed.bundleId != "*" else {
                    warnings.append("exclude '*' would hide every app, so it is ignored")
                    continue
                }
                guard !config.excludes(parsed.bundleId) else {
                    warnings.append("exclude lists '\(parsed.bundleId)' twice, the first rule is used")
                    continue
                }
                config.exclude.append(parsed)
            }
        }
        if let value = root["displayGroups"] {
            guard let groups = value as? [Any] else { throw .invalid("displayGroups must be a list") }
            for (index, group) in groups.enumerated() {
                let parsed = try displayGroup(group, index: index, warnings: &warnings)
                guard !config.displayGroups.contains(where: { $0.name == parsed.name }) else {
                    throw .invalid("displayGroups has two groups named \"\(parsed.name)\"")
                }
                config.displayGroups.append(parsed)
            }
        }
        if let value = root["appKeys"] {
            guard let bindings = value as? [String: Any] else { throw .invalid("appKeys must be an object of keys and bundle ids") }
            for name in bindings.keys.sorted() {
                guard name.count == 1, let key = name.lowercased().first, AppKey.isLetterOrDigit(key) else {
                    throw .invalid("appKeys '\(name)' must be a single letter or digit")
                }
                guard let bundleId = bindings[name] as? String, !bundleId.isEmpty else {
                    throw .invalid("appKeys.\(name) must be a bundle id")
                }
                if AppKey.reserved.contains(key) {
                    warnings.append("appKeys '\(name)' is ignored, since \(name.uppercased()) \(key == "q" ? "quits" : "hides") the selected app")
                } else if config.appKeys.contains(where: { $0.key == key }) {
                    warnings.append("appKeys lists '\(key)' twice, the first is used")
                } else {
                    config.appKeys.append(AppKey(key: key, bundleId: bundleId))
                }
            }
            config.appKeys.sort { $0.key < $1.key }
        }
        if let value = root["passThrough"] {
            guard let apps = value as? [Any] else { throw .invalid("passThrough must be a list of bundle ids") }
            for (index, app) in apps.enumerated() {
                guard let bundleId = app as? String, !bundleId.isEmpty else {
                    throw .invalid("passThrough[\(index)] must be a bundle id")
                }
                if bundleId == "*" {
                    warnings.append("passThrough '*' would give Cmd+Tab to every app, so it is ignored")
                } else if config.passesThrough(bundleId) {
                    warnings.append("passThrough lists '\(bundleId)' twice, the first is used")
                } else {
                    config.passThrough.append(bundleId)
                }
            }
        }
        if case .group(let name) = config.scope, !config.displayGroups.contains(where: { $0.name == name }) {
            warnings.append("scope uses group '\(name)', which does not exist, so all monitors are shown")
        }
        return Parsed(config: config, warnings: warnings)
    }

    private static func displayGroup(_ value: Any, index: Int, warnings: inout [String]) throws(ConfigError) -> DisplayGroup {
        guard let group = value as? [String: Any] else {
            throw .invalid("displayGroups[\(index)] must be an object with name and match")
        }
        warnings += group.keys.sorted().filter { !knownGroupKeys.contains($0) }
            .map { "unknown key 'displayGroups[\(index)].\($0)' ignored" }
        guard let name = group["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw .invalid("displayGroups[\(index)].name must be a non-empty string")
        }
        guard let match = group["match"] as? [Any] else {
            throw .invalid("displayGroups[\(index)].match must be a list of rules")
        }
        let allowed = DisplayRule.keywords.compactMap(\.keyword).map { "\"\($0)\"" }.joined(separator: ", ")
        let rules = try match.enumerated().map { ruleIndex, rule throws(ConfigError) -> DisplayRule in
            let path = "displayGroups[\(index)].match[\(ruleIndex)]"
            if let keyword = rule as? String {
                guard let parsed = DisplayRule(keyword: keyword) else {
                    throw .invalid("\(path) must be one of \(allowed), { name: \"...\" } or { uuid: \"...\" }")
                }
                return parsed
            }
            if let object = rule as? [String: Any], object.count == 1 {
                if let pattern = object["name"] as? String, !pattern.isEmpty { return .name(pattern) }
                if let uuid = object["uuid"] as? String, !uuid.isEmpty { return .uuid(uuid) }
            }
            throw .invalid("\(path) must be one of \(allowed), { name: \"...\" } or { uuid: \"...\" }")
        }
        return DisplayGroup(name: name, rules: rules)
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
    public var fileContents: String {
        let rules = exclude.map { rule in
            rule.when == .always
                ? "    \(Self.quoted(rule.bundleId)),"
                : "    { bundleId: \(Self.quoted(rule.bundleId)), when: \(Self.quoted(rule.when.rawValue)) },"
        }
        let examples = [
            "    // \"com.example.App\",",
            "    // { bundleId: \"com.apple.finder\", when: \"noWindows\" },",
        ]
        let groupLines = displayGroups.map { group in
            let match = group.rules.map { rule in
                switch rule {
                case .name(let pattern): "{ name: \(Self.quoted(pattern)) }"
                case .uuid(let uuid): "{ uuid: \(Self.quoted(uuid)) }"
                default: Self.quoted(rule.keyword ?? "")
                }
            }
            return "    { name: \(Self.quoted(group.name)), match: [\(match.joined(separator: ", "))] },"
        }
        // JSON5 names must not start with a digit unless quoted.
        let keyLines = appKeys.map { binding in
            let name = binding.key.isNumber ? Self.quoted(String(binding.key)) : String(binding.key)
            return "    \(name): \(Self.quoted(binding.bundleId)),"
        }
        let keyExamples = [
            "    // f: \"com.apple.finder\",",
            "    // \"1\": \"com.apple.Safari\",",
        ]
        let passLines = passThrough.map { "    \(Self.quoted($0))," }
        let passExamples = ["    // \"com.parallels.desktop.console\","]
        let groupExamples = [
            "    // { name: \"Laptop\", match: [\"builtIn\"] },",
            "    // { name: \"Desk\", match: [\"external\"] },",
        ]
        return """
        // Instantools Cmd+Tab settings. Edit here or in Settings; changes apply as soon as the file is saved.
        // Saving from Settings rewrites this file in this layout, so custom comments are not kept.
        {
          // Milliseconds before the switcher is drawn. A Cmd+Tab released sooner
          // switches without drawing anything. 0 draws immediately.
          showDelayMs: \(showDelayMs),

          // Which apps to list:
          //   "all"             every running app, like native Cmd+Tab
          //   "mouseDisplay"    apps with a window on the display under the mouse
          //   "focusedDisplay"  apps with a window on the display of the focused window
          //   "mouseGroup"      apps on the first group below that contains the display under the mouse
          //   "group:<name>"    apps on the displays of one group below
          scope: \(Self.quoted(scope.rawValue)),

          // Apps with no visible window (hidden, minimized or windowless):
          //   "show" in recent order, "end" after the others, or "hide".
          windowlessApps: \(Self.quoted(windowlessApps.rawValue)),

          // Icon size in points. Shrinks automatically when the apps do not fit.
          iconSize: \(Self.number(iconSize)),

          // Apps to leave out, by bundle id. A trailing * matches a prefix.
          // "when" is "always" (the default) or "noWindows".
          exclude: [
        \((rules.isEmpty ? examples : rules).joined(separator: "\n"))
          ],

          // Display groups. A display is in a group when it matches any of its rules:
          //   "builtIn", "external", "landscape", "portrait", "main" (has the menu bar),
          //   "leftmost", "rightmost", "topmost", "bottommost",
          //   { name: "DELL*" } (wildcards * and ?), or { uuid: "..." } for one specific display.
          displayGroups: [
        \((groupLines.isEmpty ? groupExamples : groupLines).joined(separator: "\n"))
          ],

          // Hold Cmd, press Tab, then one of these keys to go straight to its app, which opens if it is
          // not running. A letter or digit mapped to a bundle id. Q and H quit and hide, so they are taken.
          appKeys: {
        \((keyLines.isEmpty ? keyExamples : keyLines).joined(separator: "\n"))
          },

          // Apps that get Cmd+Tab themselves while they are in front, such as virtual machines, remote
          // desktops and games. By bundle id; a trailing * matches a prefix.
          passThrough: [
        \((passLines.isEmpty ? passExamples : passLines).joined(separator: "\n"))
          ],
        }

        """
    }

    public static var defaultFileContents: String { Config().fileContents }

    private static func quoted(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
