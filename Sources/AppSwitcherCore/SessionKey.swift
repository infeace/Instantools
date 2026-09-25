public enum KeyCode {
    public static let tab: Int64 = 48
    public static let escape: Int64 = 53
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
}

public enum SessionKey: Sendable, Equatable {
    case cancel
    case previous
    case next
    case quit
    case hide
    /// App Exposé for the selected app, on Up or Down like native Cmd+Tab.
    case expose
    /// Any letter or digit other than Q and H. It switches to the app bound to it, if there is one.
    case app(Character)

    public init?(keycode: Int64, characters: String) {
        switch keycode {
        case KeyCode.escape: self = .cancel
        case KeyCode.left: self = .previous
        case KeyCode.right: self = .next
        case KeyCode.up, KeyCode.down: self = .expose
        default:
            switch Self.character(keycode: keycode, characters: characters) {
            case "`": self = .previous
            case "q": self = .quit
            case "h": self = .hide
            case let key? where Config.AppKey.isBindable(key): self = .app(key)
            default: return nil
            }
        }
    }

    /// Holding Q must not quit one app after another.
    public var repeats: Bool {
        self == .previous || self == .next
    }

    /// Letters follow the typed character so they match the keyboard layout. When the key types anything
    /// but a single ASCII character, as on Cyrillic layouts, its US key position counts instead.
    public static func character(keycode: Int64, characters: String) -> Character? {
        if characters.count == 1, let typed = characters.lowercased().first, typed.isASCII { return typed }
        return usPositions[keycode]
    }

    private static let usPositions: [Int64: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q",
        13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k",
        45: "n", 46: "m", 50: "`",
    ]
}
