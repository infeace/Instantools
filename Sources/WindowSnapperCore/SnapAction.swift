/// Where a shortcut or a drag puts a window. The raw values are the keys in snap.json5, and Rectangle's
/// names for the same actions, so its settings import one to one.
public enum SnapAction: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case lastTwoThirds
    case maximize
    case center
    case restore
    case previousDisplay
    case nextDisplay

    public var title: String {
        switch self {
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .firstThird: "First third"
        case .centerThird: "Center third"
        case .lastThird: "Last third"
        case .firstTwoThirds: "First two thirds"
        case .lastTwoThirds: "Last two thirds"
        case .maximize: "Full screen"
        case .center: "Center"
        case .restore: "Restore"
        case .previousDisplay: "Previous monitor"
        case .nextDisplay: "Next monitor"
        }
    }

    /// Rectangle's own defaults, so its users have nothing to relearn.
    public var defaultShortcut: Shortcut? {
        let text = switch self {
        case .leftHalf: "ctrl+opt+left"
        case .rightHalf: "ctrl+opt+right"
        case .topHalf: "ctrl+opt+up"
        case .bottomHalf: "ctrl+opt+down"
        case .topLeft: "ctrl+opt+u"
        case .topRight: "ctrl+opt+i"
        case .bottomLeft: "ctrl+opt+j"
        case .bottomRight: "ctrl+opt+k"
        case .firstThird: "ctrl+opt+d"
        case .centerThird: "ctrl+opt+f"
        case .lastThird: "ctrl+opt+g"
        case .firstTwoThirds: "ctrl+opt+e"
        case .lastTwoThirds: "ctrl+opt+t"
        case .maximize: "ctrl+opt+return"
        case .center: "ctrl+opt+c"
        case .restore: "ctrl+opt+delete"
        case .previousDisplay: "ctrl+opt+cmd+left"
        case .nextDisplay: "ctrl+opt+cmd+right"
        }
        return Shortcut(text)
    }

    /// The groups Settings lists them in.
    public static let groups: [(title: String, actions: [SnapAction], footer: String?)] = [
        ("Halves", [.leftHalf, .rightHalf, .topHalf, .bottomHalf], nil),
        ("Quarters", [.topLeft, .topRight, .bottomLeft, .bottomRight], nil),
        ("Thirds", [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds], "On a portrait monitor thirds run from top to bottom."),
        ("Size", [.maximize, .center, .restore], "Restore puts a window back where it was before InstantSnap moved it."),
        ("Monitors", [.previousDisplay, .nextDisplay], "A snapped window takes the same place on the other monitor, so a half stays a half. Any other window keeps its size."),
    ]

    /// The halves that a repeated press cycles through sizes or moves to the next monitor.
    var isHalf: Bool {
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf].contains(self)
    }
}

/// What pressing the same shortcut again does.
public enum RepeatMode: String, CaseIterable, Sendable {
    /// Left half again goes to the right half of the monitor on the left, and so on across monitors.
    case nextDisplay
    /// A half again becomes two thirds, then one third, then a half.
    case cycleSizes
    case none
}
