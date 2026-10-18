import Foundation
import InstantoolsCore

/// InstantSnap's settings, in snap.json5 beside the Cmd+Tab file.
public struct SnapConfig: Sendable, Equatable {
    public static let maxGap = 40

    public var dragToSnap = true
    /// Points between snapped windows, and between them and the screen edges.
    public var gap = 0
    public var repeatMode = RepeatMode.cycleSizes
    /// Every action, nil when it has no shortcut.
    private var shortcuts: [SnapAction: Shortcut?] = Dictionary(uniqueKeysWithValues: SnapAction.allCases.map { ($0, $0.defaultShortcut) })

    public init() {}

    public func shortcut(for action: SnapAction) -> Shortcut? {
        shortcuts[action] ?? nil
    }

    public mutating func setShortcut(_ shortcut: Shortcut?, for action: SnapAction) {
        shortcuts[action] = .some(shortcut)
    }

    /// Clears each shortcut an action before it already has, going through `preferred` first and then the
    /// rest in Settings' order. Returns each cleared action with the one that keeps its shortcut.
    mutating func dropClashes(preferring preferred: Set<SnapAction>) -> [(action: SnapAction, shortcut: Shortcut, keptBy: SnapAction)] {
        var taken: [Shortcut: SnapAction] = [:]
        var dropped: [(action: SnapAction, shortcut: Shortcut, keptBy: SnapAction)] = []
        let order = SnapAction.allCases.filter(preferred.contains) + SnapAction.allCases.filter { !preferred.contains($0) }
        for action in order {
            guard let shortcut = shortcut(for: action) else { continue }
            if let owner = taken[shortcut] {
                dropped.append((action, shortcut, owner))
                setShortcut(nil, for: action)
            } else {
                taken[shortcut] = action
            }
        }
        return dropped
    }

    /// The actions with a shortcut, in the order Settings lists them.
    public var boundShortcuts: [(action: SnapAction, shortcut: Shortcut)] {
        SnapAction.allCases.compactMap { action in shortcut(for: action).map { (action, $0) } }
    }
}

extension SnapConfig: ConfigFile {
    public static let fileName = "snap.json5"

    private static let knownKeys: Set = ["dragToSnap", "gap", "repeat", "shortcuts"]

    public static func parse(_ data: Data) throws(ConfigError) -> ParsedConfig<SnapConfig> {
        let root = try ConfigValues.object(from: data)
        var config = SnapConfig()
        var warnings = root.keys.sorted().filter { !knownKeys.contains($0) }.map { "unknown key '\($0)' ignored" }

        if let value = root["dragToSnap"] {
            guard ConfigValues.isBoolean(value), let flag = value as? Bool else { throw .invalid("dragToSnap must be true or false") }
            config.dragToSnap = flag
        }
        if let value = root["gap"] {
            guard !ConfigValues.isBoolean(value), let number = value as? Int, (0...maxGap).contains(number) else {
                throw .invalid("gap must be a whole number from 0 to \(maxGap)")
            }
            config.gap = number
        }
        if let value = root["repeat"] {
            config.repeatMode = try ConfigValues.enumValue("repeat", value)
        }
        if let value = root["shortcuts"] {
            guard let entries = value as? [String: Any] else { throw .invalid("shortcuts must be an object of actions and keys") }
            for action in SnapAction.allCases {
                guard let entry = entries[action.rawValue] else { continue }
                guard let text = entry as? String else {
                    throw .invalid("shortcuts.\(action.rawValue) must be keys such as \"ctrl+opt+left\", or \"\" for none")
                }
                if text.isEmpty {
                    config.setShortcut(nil, for: action)
                    continue
                }
                guard let shortcut = Shortcut(text) else {
                    throw .invalid("shortcuts.\(action.rawValue) '\(text)' must be keys such as \"ctrl+opt+left\", with ctrl, opt or cmd unless the key is f1 to f20")
                }
                config.setShortcut(shortcut, for: action)
            }
            warnings += entries.keys.sorted().filter { SnapAction(rawValue: $0) == nil }.map { "unknown action 'shortcuts.\($0)' ignored" }
            // An action left at its default can clash with one the file sets, so clashes are settled once all
            // are read: one set in the file wins over a default, and otherwise the first in Settings' order.
            let explicit = Set(entries.keys.compactMap(SnapAction.init(rawValue:)))
            for clash in config.dropClashes(preferring: explicit) where explicit.contains(clash.action) {
                warnings.append("shortcuts.\(clash.action.rawValue) uses \(clash.shortcut.text) like shortcuts.\(clash.keptBy.rawValue), which keeps it")
            }
        }
        return ParsedConfig(config: config, warnings: warnings)
    }

    public var fileContents: String {
        let width = SnapAction.allCases.map(\.rawValue.count).max() ?? 0
        let shortcutLines = SnapAction.allCases.map { action in
            let name = "\(action.rawValue):".padding(toLength: width + 1, withPad: " ", startingAt: 0)
            return "    \(name) \(ConfigValues.quoted(shortcut(for: action)?.text ?? "")),"
        }
        return """
        // Instantools InstantSnap settings. Edit here or in Settings; changes apply as soon as the file is saved.
        // Saving from Settings rewrites this file in this layout, so custom comments are not kept.
        {
          // Drag a window by its title bar to an edge or a corner of the screen to snap it there.
          dragToSnap: \(dragToSnap),

          // Points between snapped windows, and between them and the edges of the screen. 0 to \(Self.maxGap).
          gap: \(gap),

          // Pressing the shortcut of a half again:
          //   "nextDisplay"  left and right go on to the next monitor that way, like Windows
          //   "cycleSizes"   the half becomes two thirds, then one third, then a half again
          //   "none"         nothing more happens
          repeat: \(ConfigValues.quoted(repeatMode.rawValue)),

          // Keys for each action, such as "ctrl+opt+left", or "" for none. Modifiers: ctrl, opt, shift, cmd,
          // with at least one of ctrl, opt and cmd unless the key is f1 to f20. Keys: a to z, 0 to 9, left, right, up, down, return,
          // delete, forwardDelete, space, tab, escape, home, end, pageUp, pageDown, f1 to f20, and - = [ ] ; ' , . / \\ `.
          // Letters are the keys where they sit on a US keyboard, in every layout.
          shortcuts: {
        \(shortcutLines.joined(separator: "\n"))
          },
        }

        """
    }
}
