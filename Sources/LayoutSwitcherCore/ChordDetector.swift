/// The modifiers that matter for the chord. Caps Lock's toggle state is left out, so the chord still works
/// with Caps Lock on.
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let command = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let option = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    public static let chord: Modifiers = [.control, .command]

    /// From a CGEventFlags raw value. Only the device-independent bits, so left and right keys count the same.
    public init(eventFlags: UInt64) {
        self = []
        if eventFlags & 0x40000 != 0 { insert(.control) }
        if eventFlags & 0x100000 != 0 { insert(.command) }
        if eventFlags & 0x20000 != 0 { insert(.shift) }
        if eventFlags & 0x80000 != 0 { insert(.option) }
        if eventFlags & 0x800000 != 0 { insert(.function) }
    }
}

/// Switches when pressing Control or Command makes the held modifiers exactly Control+Command, in either
/// order. Keys pressed around it never undo it: when typing fast, the next letter often lands before the
/// chord is let go.
public struct ChordDetector: Sendable {
    private var held: Modifiers = []

    public init() {}

    /// True when this change should switch the layout. `modifiers` comes from each event's full flags, so one
    /// missed event cannot leave the state stuck. Letting go of Shift from Ctrl+Cmd+Shift also leaves exactly
    /// Control+Command, but that is the end of a shortcut, not a chord.
    public mutating func modifiersChanged(to modifiers: Modifiers) -> Bool {
        defer { held = modifiers }
        return modifiers == .chord && held.isStrictSubset(of: .chord)
    }

    /// For when events may have been missed, such as across sleep or while the tap was off. `held` is what is
    /// down right now, so letting go of Shift from a Ctrl+Cmd+Shift held across the gap is still not a chord.
    public mutating func reset(to held: Modifiers) {
        self.held = held
    }
}
