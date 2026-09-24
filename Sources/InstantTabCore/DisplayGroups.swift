import CoreGraphics
import Foundation

/// A rule for which displays belong to a group. Rules describe displays rather than naming them where
/// possible, so a group survives swapping monitors.
public enum DisplayRule: Sendable, Hashable {
    case builtIn
    case external
    case landscape
    case portrait
    /// The display with the menu bar.
    case main
    case leftmost
    case rightmost
    case topmost
    case bottommost
    /// The display's name, case-insensitive, with `*` and `?` wildcards.
    case name(String)
    /// One specific display. Identical monitors can swap ids, so prefer the other rules.
    case uuid(String)

    public static let keywords: [DisplayRule] = [
        .builtIn, .external, .landscape, .portrait, .main, .leftmost, .rightmost, .topmost, .bottommost,
    ]

    public var keyword: String? {
        switch self {
        case .builtIn: "builtIn"
        case .external: "external"
        case .landscape: "landscape"
        case .portrait: "portrait"
        case .main: "main"
        case .leftmost: "leftmost"
        case .rightmost: "rightmost"
        case .topmost: "topmost"
        case .bottommost: "bottommost"
        case .name, .uuid: nil
        }
    }

    public init?(keyword: String) {
        guard let rule = Self.keywords.first(where: { $0.keyword == keyword }) else { return nil }
        self = rule
    }

    /// Position rules compare against the other connected displays.
    public func matches(_ display: Display, among displays: [Display]) -> Bool {
        switch self {
        case .builtIn: display.isBuiltIn
        case .external: !display.isBuiltIn
        case .landscape: display.frame.width >= display.frame.height
        case .portrait: display.frame.height > display.frame.width
        case .main: display.isMain
        case .leftmost: display.frame.minX == displays.map(\.frame.minX).min()
        case .rightmost: display.frame.maxX == displays.map(\.frame.maxX).max()
        // CoreGraphics coordinates grow downwards.
        case .topmost: display.frame.minY == displays.map(\.frame.minY).min()
        case .bottommost: display.frame.maxY == displays.map(\.frame.maxY).max()
        case .name(let pattern): NSPredicate(format: "SELF LIKE[c] %@", pattern).evaluate(with: display.name)
        case .uuid(let uuid): display.uuid.caseInsensitiveCompare(uuid) == .orderedSame
        }
    }
}

/// A named set of displays. A display is in the group when it matches any of the rules.
public struct DisplayGroup: Sendable, Equatable {
    public var name: String
    public var rules: [DisplayRule]

    public init(name: String, rules: [DisplayRule]) {
        self.name = name
        self.rules = rules
    }

    public func members(in displays: [Display]) -> Set<UInt32> {
        Set(displays.filter { display in rules.contains { $0.matches(display, among: displays) } }.map(\.id))
    }
}

/// Group membership for the displays connected right now. Computed when displays or config change,
/// so the key press only looks sets up.
public struct ResolvedGroups: Sendable, Equatable {
    public var groups: [(name: String, members: Set<UInt32>)]

    public init(_ groups: [DisplayGroup], displays: [Display]) {
        self.groups = groups.map { ($0.name, $0.members(in: displays)) }
    }

    public func members(of name: String) -> Set<UInt32>? {
        groups.first { $0.name == name }?.members
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.groups.map(\.name) == rhs.groups.map(\.name) && lhs.groups.map(\.members) == rhs.groups.map(\.members)
    }
}

public enum DisplayScope {
    /// The displays the switcher lists apps from, or nil for every display. Anything that cannot be
    /// resolved (no mouse display, a missing or disconnected group) falls back to every display.
    public static func targets(
        for scope: Config.Scope,
        groups: ResolvedGroups,
        mouseDisplay: UInt32?,
        focusedDisplay: UInt32?
    ) -> Set<UInt32>? {
        switch scope {
        case .all:
            return nil
        case .mouseDisplay:
            return mouseDisplay.map { [$0] }
        case .focusedDisplay:
            return (focusedDisplay ?? mouseDisplay).map { [$0] }
        case .mouseGroup:
            guard let mouseDisplay else { return nil }
            return groups.groups.first { $0.members.contains(mouseDisplay) }?.members ?? [mouseDisplay]
        case .group(let name):
            guard let members = groups.members(of: name), !members.isEmpty else { return nil }
            return members
        }
    }

    /// The display showing the frontmost app's frontmost window.
    public static func focusedDisplay(in snapshot: Snapshot, frontmostPid: Int32?, displays: [Display]) -> UInt32? {
        guard let frontmostPid, let window = snapshot.windows.first(where: { $0.pid == frontmostPid }) else { return nil }
        return DisplayMapping.display(for: window.frame, in: displays)
    }
}
