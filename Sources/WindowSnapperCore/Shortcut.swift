/// A key with modifiers, written as `ctrl+opt+left` in snap.json5. Keys are physical positions, as macOS
/// virtual key codes, so a shortcut stays on the same key in every keyboard layout.
public struct Shortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)

        /// In the order macOS menus show them.
        static let ordered: [(modifier: Modifiers, name: String, symbol: String, label: String)] = [
            (.control, "ctrl", "⌃", "control"), (.option, "opt", "⌥", "option"), (.shift, "shift", "⇧", "shift"),
            (.command, "cmd", "⌘", "command"),
        ]
    }

    public let keyCode: UInt16
    public let modifiers: Modifiers

    /// Nil for an unknown key, and for one without Control, Option or Command, which would take the key away
    /// from typing everywhere. Function keys need none.
    init?(keyCode: UInt16, modifiers: Modifiers) {
        guard let key = Self.keys.first(where: { $0.code == keyCode }),
              key.isFunctionKey || !modifiers.isDisjoint(with: [.control, .option, .command])
        else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Nil for an unknown key or modifier, and where `init(keyCode:modifiers:)` is. Also takes spaces, and the
    /// symbols Settings shows, as in ⌃⌥←.
    public init?(_ text: String) {
        var spelled = ""
        for character in text.lowercased() where !character.isWhitespace {
            if let modifier = Modifiers.ordered.first(where: { $0.symbol == String(character) }) {
                spelled += modifier.name + "+"
            } else {
                spelled.append(character)
            }
        }
        if spelled.hasSuffix("+") { return nil }
        let parts = spelled.split(separator: "+").map(String.init)
        guard let keyName = parts.last else { return nil }
        var modifiers: Modifiers = []
        for part in parts.dropLast() {
            guard let modifier = Self.modifierNames[part], !modifiers.contains(modifier) else { return nil }
            modifiers.insert(modifier)
        }
        guard let key = Self.keys.first(where: { [$0.name.lowercased(), $0.symbol.lowercased()].contains(keyName) || $0.aliases.contains(keyName) })
        else { return nil }
        self.init(keyCode: key.code, modifiers: modifiers)
    }

    /// As written in the file: `ctrl+opt+left`.
    public var text: String {
        let names = Modifiers.ordered.filter { modifiers.contains($0.modifier) }.map(\.name)
        return (names + [key.name]).joined(separator: "+")
    }

    /// As macOS menus show it: ⌃⌥←.
    public var symbols: String {
        Modifiers.ordered.filter { modifiers.contains($0.modifier) }.map(\.symbol).joined() + key.symbol
    }

    /// One per key, as key caps show them: ⌃ control, ⌥ option, ← left.
    public var keyCaps: [(symbol: String, label: String)] {
        Modifiers.ordered.filter { modifiers.contains($0.modifier) }.map { ($0.symbol, $0.label) } + [(key.symbol, key.name)]
    }

    private var key: Key {
        Self.keys.first { $0.code == keyCode }!
    }

    private struct Key {
        let code: UInt16
        let name: String
        let symbol: String
        var aliases: [String] = []

        var isFunctionKey: Bool {
            name.count > 1 && name.first == "f" && name.dropFirst().allSatisfy(\.isNumber)
        }
    }

    private static let modifierNames: [String: Modifiers] = [
        "ctrl": .control, "control": .control,
        "opt": .option, "option": .option, "alt": .option,
        "shift": .shift,
        "cmd": .command, "command": .command,
    ]

    /// ANSI positions from Carbon's Events.h.
    private static let keys: [Key] = {
        let letters: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
            ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("o", 31), ("u", 32),
            ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        let digits: [(String, UInt16)] = [
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29),
        ]
        let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        var keys = letters.map { Key(code: $0.1, name: $0.0, symbol: $0.0.uppercased()) }
            + digits.map { Key(code: $0.1, name: $0.0, symbol: $0.0) }
            + functionKeys.enumerated().map { Key(code: $0.element, name: "f\($0.offset + 1)", symbol: "F\($0.offset + 1)") }
        keys += [
            Key(code: 123, name: "left", symbol: "←"),
            Key(code: 124, name: "right", symbol: "→"),
            Key(code: 125, name: "down", symbol: "↓"),
            Key(code: 126, name: "up", symbol: "↑"),
            Key(code: 36, name: "return", symbol: "↩", aliases: ["enter"]),
            Key(code: 51, name: "delete", symbol: "⌫", aliases: ["backspace"]),
            Key(code: 117, name: "forwardDelete", symbol: "⌦"),
            Key(code: 49, name: "space", symbol: "Space"),
            Key(code: 48, name: "tab", symbol: "⇥"),
            Key(code: 53, name: "escape", symbol: "⎋", aliases: ["esc"]),
            Key(code: 115, name: "home", symbol: "↖"),
            Key(code: 119, name: "end", symbol: "↘"),
            Key(code: 116, name: "pageUp", symbol: "⇞"),
            Key(code: 121, name: "pageDown", symbol: "⇟"),
            Key(code: 27, name: "-", symbol: "-", aliases: ["minus"]),
            Key(code: 24, name: "=", symbol: "=", aliases: ["equal"]),
            Key(code: 33, name: "[", symbol: "["),
            Key(code: 30, name: "]", symbol: "]"),
            Key(code: 41, name: ";", symbol: ";"),
            Key(code: 39, name: "'", symbol: "'"),
            Key(code: 43, name: ",", symbol: ","),
            Key(code: 47, name: ".", symbol: "."),
            Key(code: 44, name: "/", symbol: "/"),
            Key(code: 42, name: "\\", symbol: "\\"),
            Key(code: 50, name: "`", symbol: "`"),
        ]
        return keys
    }()
}
