extension Config {
    /// Cmd+Tab, then this key, goes straight to the app.
    public struct AppKey: Sendable, Equatable {
        public var key: Character
        public var bundleId: String

        public init(key: Character, bundleId: String) {
            self.key = key
            self.bundleId = bundleId
        }

        public static func isLetterOrDigit(_ key: Character) -> Bool {
            key.isASCII && (key.isLowercase || key.isNumber)
        }

        /// Q and H stay with quit and hide, like native Cmd+Tab.
        public static func isBindable(_ key: Character) -> Bool {
            isLetterOrDigit(key) && !reserved.contains(key)
        }

        public static let reserved: Set<Character> = ["q", "h"]
    }

    public enum AppKeyProblem: Equatable, Sendable {
        case notALetterOrDigit
        case reserved(Character)
        case taken(bundleId: String)
    }

    /// Why `key` cannot be bound, or nil if it can. `current` is the key being changed, if any.
    public func appKeyProblem(_ key: Character?, replacing current: Character? = nil) -> AppKeyProblem? {
        guard let key, AppKey.isLetterOrDigit(key) else { return .notALetterOrDigit }
        if AppKey.reserved.contains(key) { return .reserved(key) }
        if key != current, let owner = appKeys.first(where: { $0.key == key }) { return .taken(bundleId: owner.bundleId) }
        return nil
    }

    /// Kept sorted by key, so the file and Settings list them in a stable order.
    public mutating func bindAppKey(_ key: Character, to bundleId: String, replacing current: Character? = nil) {
        appKeys.removeAll { $0.key == key || $0.key == current }
        appKeys.append(AppKey(key: key, bundleId: bundleId))
        appKeys.sort { $0.key < $1.key }
    }
}

/// Built once per config, so a key press only does dictionary lookups. Bundle ids are case-insensitive.
public struct AppKeyMap: Sendable {
    private let bundleIds: [Character: String]
    private let keys: [String: Character]

    public init(_ appKeys: [Config.AppKey]) {
        bundleIds = Dictionary(appKeys.map { ($0.key, $0.bundleId) }, uniquingKeysWith: { first, _ in first })
        keys = Dictionary(appKeys.map { ($0.bundleId.lowercased(), $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    public func bundleId(for key: Character) -> String? {
        bundleIds[key]
    }

    /// The key shown on an app's tile. An app with several keys shows the first.
    public func key(for bundleId: String?) -> Character? {
        guard let bundleId, !keys.isEmpty else { return nil }
        return keys[bundleId.lowercased()]
    }
}

public enum AppKeyTarget: Equatable, Sendable {
    case running(SwitcherEntry)
    case launch(bundleId: String)
}

extension SwitcherFilter {
    /// A binding reaches its app even when it is excluded or on another display, since it was asked for by
    /// name. Its tile is used when it has one, otherwise its frontmost window.
    public static func target(forAppKey key: Character, appKeys: AppKeyMap, in snapshot: Snapshot, listed: [SwitcherEntry]) -> AppKeyTarget? {
        guard let bundleId = appKeys.bundleId(for: key) else { return nil }
        guard let app = snapshot.apps.first(where: { $0.bundleId?.caseInsensitiveCompare(bundleId) == .orderedSame }) else {
            return .launch(bundleId: bundleId)
        }
        if let entry = listed.first(where: { $0.pid == app.pid }) { return .running(entry) }
        let window = snapshot.windows.first { $0.pid == app.pid }
        return .running(SwitcherEntry(pid: app.pid, name: app.name, windowId: window?.id, key: key, isHidden: app.isHidden))
    }
}
