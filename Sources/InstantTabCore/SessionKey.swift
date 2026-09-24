public enum KeyCode {
    public static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let q: Int64 = 12
    static let h: Int64 = 4
    static let grave: Int64 = 50
}

public enum SessionKey: Sendable, Equatable {
    case cancel
    case previous
    case next
    case quit
    case hide

    /// Letters follow the typed character so they match the keyboard layout. When the key types anything
    /// but a single ASCII character, as on Cyrillic layouts, its US key position counts instead.
    public init?(keycode: Int64, characters: String) {
        let ascii = characters.count == 1 && characters.allSatisfy(\.isASCII) ? characters.lowercased() : nil
        switch (keycode, ascii ?? Self.usPositions[keycode]) {
        case (KeyCode.escape, _): self = .cancel
        case (KeyCode.left, _), (_, "`"): self = .previous
        case (KeyCode.right, _): self = .next
        case (_, "q"): self = .quit
        case (_, "h"): self = .hide
        default: return nil
        }
    }

    /// Holding Q must not quit one app after another.
    public var repeats: Bool {
        self == .previous || self == .next
    }

    private static let usPositions: [Int64: String] = [KeyCode.q: "q", KeyCode.h: "h", KeyCode.grave: "`"]
}
