/// The layout used before the current one, tracked here rather than read back from macOS, so a second
/// switch right after the first never waits on a notification.
public struct LayoutHistory: Sendable {
    public private(set) var current: String?
    public private(set) var previous: String?

    public init(current: String? = nil) { self.current = current }

    public mutating func observe(_ id: String) {
        guard id != current else { return }
        previous = current
        current = id
    }
}

public enum LayoutPicker {
    /// The previous layout, like Ctrl+Space, else the next one in the list. With two layouts it always flips
    /// between them. Nil when there is nothing else to switch to.
    public static func target(among layouts: [String], current: String?, previous: String?) -> String? {
        if let previous, previous != current, layouts.contains(previous) { return previous }
        guard let current, let index = layouts.firstIndex(of: current) else { return layouts.first }
        let next = layouts[(index + 1) % layouts.count]
        return next == current ? nil : next
    }
}
