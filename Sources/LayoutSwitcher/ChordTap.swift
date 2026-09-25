import CoreGraphics
import InstantoolsKit
import LayoutSwitcherCore

/// Listen-only, so input is never held back and a crash cannot break the keyboard. It sits on the main run
/// loop so the switch runs inside the callback, where TIS needs it, with no hop in between.
@MainActor
final class ChordTap {
    var onChord: (() -> Void)?
    private var detector = ChordDetector()
    private var tap: CFMachPort?

    /// Input Monitoring switched off after start leaves the tap running but deaf. The host checks for that
    /// itself, since the check takes about 10 ms on this run loop.
    var isRunning: Bool {
        guard let tap else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    /// False until the Input Monitoring check passes, which Accessibility alone also does unless Input
    /// Monitoring was switched off. Without it macOS still creates the tap, minus the keyboard.
    func start() -> Bool {
        if let tap, CFMachPortIsValid(tap) { return true }
        guard Permissions.inputMonitoring else { return false }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let chordTap = Unmanaged<ChordTap>.fromOpaque(userInfo).takeUnretainedValue()
                    let flags = event.flags.rawValue
                    MainActor.assumeIsolated { chordTap.handle(type, flags: flags) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
        return true
    }

    /// After sleep or a user switch, events may have been missed and macOS may have turned the tap off. False
    /// when that leaves no tap, so the caller can wait for the permission again.
    func recover() -> Bool {
        detector.reset()
        if let tap, !CFMachPortIsValid(tap) { self.tap = nil }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard start() else {
            Diagnostics.log.error("could not recreate the event tap")
            return false
        }
        return true
    }

    private func handle(_ type: CGEventType, flags: UInt64) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            detector.reset()
            Diagnostics.log.notice("event tap was turned off by macOS, turned back on")
        case .flagsChanged:
            if detector.modifiersChanged(to: Modifiers(eventFlags: flags)) { onChord?() }
        default:
            break
        }
    }
}
