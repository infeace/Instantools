import Foundation

/// Rectangle's settings, read from its defaults, so InstantSnap starts out where Rectangle left off.
public enum RectangleImport {
    public static let bundleId = "com.knollsoft.Rectangle"

    private static let settingKeys: Set = ["alternateDefaultShortcuts", "subsequentExecutionMode", "gapSize", "windowSnapping"]

    public static func hasSettings(_ defaults: [String: Any]) -> Bool {
        defaults.keys.contains { SnapAction(rawValue: $0) != nil || settingKeys.contains($0) }
    }

    /// Rectangle keeps only the shortcuts changed from its defaults, with an empty entry for one that was
    /// cleared. Its defaults are InstantSnap's, or Spectacle's when that set was picked in its welcome window.
    /// A key InstantSnap has no name for, such as one on the keypad, leaves the action without a shortcut
    /// rather than back on a default the user had moved it away from.
    public static func config(from defaults: [String: Any]) -> SnapConfig {
        var config = SnapConfig()
        // Rectangle reads a missing value as false, which is the Spectacle set.
        if (defaults["alternateDefaultShortcuts"] as? NSNumber)?.boolValue != true {
            for action in SnapAction.allCases {
                config.setShortcut(spectacleShortcut(for: action), for: action)
            }
        }
        var changed = Set<SnapAction>()
        for action in SnapAction.allCases {
            guard let entry = defaults[action.rawValue] as? [String: Any] else { continue }
            changed.insert(action)
            let keyCode = (entry["keyCode"] as? NSNumber).flatMap { UInt16(exactly: $0.intValue) }
            let flags = (entry["modifierFlags"] as? NSNumber)?.uintValue
            let shortcut = keyCode.flatMap { code in flags.flatMap { Shortcut(keyCode: code, modifiers: modifiers(fromEventFlags: $0)) } }
            config.setShortcut(shortcut, for: action)
        }
        // A shortcut moved to another action leaves the default of the first one behind.
        _ = config.dropClashes(preferring: changed)
        // Rectangle's values: 0 cycles sizes, 1 moves across monitors, 2 does nothing, 3 cycles sizes and then
        // moves across, 4 cycles through monitors.
        switch (defaults["subsequentExecutionMode"] as? NSNumber)?.intValue {
        case 0: config.repeatMode = .cycleSizes
        case 1, 3, 4: config.repeatMode = .nextDisplay
        case 2: config.repeatMode = .none
        default: break
        }
        if let gap = (defaults["gapSize"] as? NSNumber)?.doubleValue, gap.isFinite {
            config.gap = Int(min(max(gap, 0), Double(SnapConfig.maxGap)).rounded())
        }
        // 2 is snapping turned off in Rectangle.
        if (defaults["windowSnapping"] as? NSNumber)?.intValue == 2 {
            config.dragToSnap = false
        }
        return config
    }

    /// Rectangle's Spectacle set, for the actions InstantSnap has.
    private static func spectacleShortcut(for action: SnapAction) -> Shortcut? {
        let text: String? = switch action {
        case .leftHalf: "opt+cmd+left"
        case .rightHalf: "opt+cmd+right"
        case .topHalf: "opt+cmd+up"
        case .bottomHalf: "opt+cmd+down"
        case .topLeft: "ctrl+cmd+left"
        case .topRight: "ctrl+cmd+right"
        case .bottomLeft: "ctrl+shift+cmd+left"
        case .bottomRight: "ctrl+shift+cmd+right"
        case .maximize: "opt+cmd+f"
        case .center: "opt+cmd+c"
        case .restore: "ctrl+opt+delete"
        case .previousDisplay: "ctrl+opt+cmd+left"
        case .nextDisplay: "ctrl+opt+cmd+right"
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds: nil
        }
        return text.flatMap(Shortcut.init)
    }

    /// NSEvent modifier flags, as Rectangle stores them.
    static func modifiers(fromEventFlags flags: UInt) -> Shortcut.Modifiers {
        var modifiers: Shortcut.Modifiers = []
        if flags & (1 << 17) != 0 { modifiers.insert(.shift) }
        if flags & (1 << 18) != 0 { modifiers.insert(.control) }
        if flags & (1 << 19) != 0 { modifiers.insert(.option) }
        if flags & (1 << 20) != 0 { modifiers.insert(.command) }
        return modifiers
    }
}
