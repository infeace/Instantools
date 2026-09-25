/// Case-insensitive matching of a display name, with `*` for any run of characters and `?` for one. A
/// backslash makes the next character literal, as NSPredicate's LIKE did, and a trailing one is literal too,
/// where LIKE threw an exception that ended the process.
enum Wildcard {
    private enum Token: Equatable {
        case literal(Character)
        case one
        case any
    }

    static func matches(_ pattern: String, _ name: String) -> Bool {
        let tokens = tokens(pattern.lowercased())
        let name = Array(name.lowercased())
        var t = 0
        var n = 0
        // The last `*` and where in the name it began, to widen it on a mismatch.
        var star: (token: Int, name: Int)?
        while n < name.count {
            if t < tokens.count, tokens[t] == .any {
                star = (t, n)
                t += 1
            } else if t < tokens.count, tokens[t] == .one || tokens[t] == .literal(name[n]) {
                t += 1
                n += 1
            } else if let last = star {
                star = (last.token, last.name + 1)
                t = last.token + 1
                n = last.name + 1
            } else {
                return false
            }
        }
        while t < tokens.count, tokens[t] == .any { t += 1 }
        return t == tokens.count
    }

    private static func tokens(_ pattern: String) -> [Token] {
        var tokens: [Token] = []
        var escaped = false
        for character in pattern {
            if escaped {
                tokens.append(.literal(character))
                escaped = false
                continue
            }
            switch character {
            case "\\": escaped = true
            case "*": tokens.append(.any)
            case "?": tokens.append(.one)
            default: tokens.append(.literal(character))
            }
        }
        if escaped { tokens.append(.literal("\\")) }
        return tokens
    }
}
