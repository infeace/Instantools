import Testing
@testable import LayoutSwitcherCore

struct ChordDetectorTests {
    /// Feeds modifier states in order and returns the index of each one that switched.
    private func switches(_ steps: [Modifiers], _ detector: inout ChordDetector) -> [Int] {
        steps.indices.filter { detector.modifiersChanged(to: steps[$0]) }
    }

    private func switches(_ steps: [Modifiers]) -> [Int] {
        var detector = ChordDetector()
        return switches(steps, &detector)
    }

    @Test func eitherOrderSwitchesOnPress() {
        #expect(switches([[.control], .chord, [.command], []]) == [1])
        #expect(switches([[.command], .chord, [.control], []]) == [1])
    }

    @Test func holdingCommandAndTappingControlSwitchesEachTime() {
        #expect(switches([[.command], .chord, [.command], .chord, [.command], []]) == [1, 3])
    }

    @Test func typingRightAfterTheChordKeepsTheSwitch() {
        // A capital letter typed while Command is still coming up: Shift joins, then everything lifts.
        #expect(switches([[.control], .chord, [.control, .command, .shift], [.shift], []]) == [1])
    }

    @Test func shiftLetGoJustBeforeTheChordStillSwitches() {
        // "H" typed, then Caps lands before Shift is released.
        #expect(switches([[.shift], [.shift, .control], [.control], .chord, []]) == [3])
    }

    @Test func otherModifierHeldThroughTheChordNeverSwitches() {
        #expect(switches([[.shift], [.shift, .control], [.shift, .control, .command], []]).isEmpty)
        #expect(switches([[.option], [.option, .control, .command], []]).isEmpty)
        #expect(switches([[.function], [.function, .control, .command], []]).isEmpty)
    }

    @Test func lettingGoOfShiftIntoTheChordIsNotAChord() {
        // Ctrl+Cmd+Shift+4 with Shift released first.
        #expect(switches([[.command], [.command, .shift], [.command, .shift, .control], .chord, [.command], []]).isEmpty)
    }

    @Test func secondControlKeyDoesNotSwitchAgain() {
        // Left and right Control share the device-independent flag, so the state repeats.
        #expect(switches([[.control], .chord, .chord, .chord]) == [1])
    }

    @Test func resetForgetsAStaleChord() {
        var detector = ChordDetector()
        #expect(switches([[.control], .chord], &detector) == [1])
        detector.reset(to: []) // The releases were missed across sleep.
        #expect(switches([.chord], &detector) == [0])
    }

    @Test func resetKeepsWhatIsStillHeld() {
        var detector = ChordDetector()
        // Ctrl+Cmd+Shift held across sleep, then Shift let go first.
        detector.reset(to: [.control, .command, .shift])
        #expect(switches([.chord, [.command], []], &detector).isEmpty)

        // Ctrl+Cmd held across it: no switch until Control is pressed again.
        detector.reset(to: .chord)
        #expect(switches([.chord, [.command], .chord], &detector) == [2])
    }

    @Test func modifiersFromEventFlags() {
        #expect(Modifiers(eventFlags: 0x40000 | 0x100000) == .chord)
        #expect(Modifiers(eventFlags: 0x40001 | 0x100008) == .chord) // Device bits for the left keys.
        #expect(Modifiers(eventFlags: 0x42000 | 0x100010) == .chord) // Right Control, as Caps Lock remaps to.
        #expect(Modifiers(eventFlags: 0x40000 | 0x100000 | 0x10000) == .chord) // Caps Lock on.
        #expect(Modifiers(eventFlags: 0x20000 | 0x80000 | 0x800000) == [.shift, .option, .function])
        #expect(Modifiers(eventFlags: 0x100) == [])
    }
}
