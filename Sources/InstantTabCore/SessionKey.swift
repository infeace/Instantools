/// Keys that act on the open switcher while Cmd is held.
public enum SessionKey: Sendable, Equatable {
    case cancel
    case previous
    case next
    case quit
    case hide

    /// Letters follow the typed character so they match the keyboard layout. Layouts that type no Latin
    /// letter fall back to the US key position.
    public init?(keycode: Int64, characters: String) {
        let latin = characters.count == 1 && characters.allSatisfy(\.isASCII) ? characters.lowercased() : nil
        switch (keycode, latin ?? Self.usPositions[keycode]) {
        case (53, _): self = .cancel
        case (123, _), (_, "`"): self = .previous
        case (124, _): self = .next
        case (_, "q"): self = .quit
        case (_, "h"): self = .hide
        default: return nil
        }
    }

    /// Holding Q must not quit one app after another.
    public var repeats: Bool {
        self == .previous || self == .next
    }

    private static let usPositions: [Int64: String] = [12: "q", 4: "h", 50: "`"]
}
