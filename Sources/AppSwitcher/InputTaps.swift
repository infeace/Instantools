import AppSwitcherCore
import CoreGraphics
import Foundation
import InstantoolsKit
import os

/// On their own thread so a busy main thread never delays the keyboard. The session tap swallows keys, so
/// it is on only while the switcher is open (always on, it breaks input methods), and sits at the HID
/// level to see Cmd+Esc before Game Overlay does.
final class InputTaps: @unchecked Sendable {
    /// The taps are replaced when recovering, so they sit behind the lock with the session flag.
    private struct State: @unchecked Sendable {
        var sessionActive = false
        var modifierTap: CFMachPort?
        var sessionTap: CFMachPort?
        var runLoop: CFRunLoop?
    }

    /// Lets a port leave the lock. The taps were always used from both main and the tap thread.
    private struct UncheckedPort: @unchecked Sendable {
        let port: CFMachPort
    }

    /// Gets the release event's own time in uptime nanoseconds, or 0 when it cannot be converted.
    private let onCommandReleased: @Sendable (UInt64) -> Void
    private let onSessionKey: @Sendable (SessionKey) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    init(onCommandReleased: @escaping @Sendable (UInt64) -> Void, onSessionKey: @escaping @Sendable (SessionKey) -> Void) {
        self.onCommandReleased = onCommandReleased
        self.onSessionKey = onSessionKey
    }

    /// False until macOS allows both taps, so callers can retry once permissions are granted.
    func start() -> Bool {
        if state.withLock({ $0.modifierTap != nil }) { return true }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let created = createTaps()
            ready.signal()
            guard created else { return }
            CFRunLoopRun()
        }
        thread.name = "com.infeace.Instantools.input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return state.withLock { $0.modifierTap != nil }
    }

    /// After sleep or a user switch, events may have been missed and macOS may have turned a tap off or
    /// invalidated its port. A port that is gone takes both taps and their thread down to start over. False
    /// when that leaves no taps, so the caller can wait for the permissions again.
    func recover() -> Bool {
        let current = state.withLock { $0 }
        guard let modifier = current.modifierTap, let session = current.sessionTap else { return false }
        if CFMachPortIsValid(modifier), CFMachPortIsValid(session) {
            if !CGEvent.tapIsEnabled(tap: modifier) {
                CGEvent.tapEnable(tap: modifier, enable: true)
                Diagnostics.log.notice("modifier tap was off, turned back on")
            }
            return true
        }
        state.withLock { state in
            state.modifierTap = nil
            state.sessionTap = nil
            state.runLoop = nil
        }
        CFMachPortInvalidate(modifier)
        CFMachPortInvalidate(session)
        if let runLoop = current.runLoop { CFRunLoopStop(runLoop) }
        guard start() else {
            Diagnostics.log.error("could not recreate the input taps")
            return false
        }
        Diagnostics.log.notice("input taps were invalid, recreated")
        return true
    }

    func setSessionActive(_ active: Bool) {
        let sessionTap = state.withLock { state in
            state.sessionActive = active
            return state.sessionTap.map(UncheckedPort.init)
        }
        if let sessionTap { follow(sessionTap.port, enabled: nil) }
    }

    /// Sets the session tap to the session flag outside the lock, since the tap's callback takes the lock
    /// and enabling is a WindowServer call, which could wait on an event that callback holds. The flag is
    /// read again after each call, so a change that raced it, from main or the tap thread, is applied too.
    /// `enabled` is the tap's state if known, which saves a call that would change nothing.
    private func follow(_ sessionTap: CFMachPort, enabled: Bool?) {
        var applied = enabled
        while true {
            let active = state.withLock { $0.sessionActive }
            if active == applied { return }
            CGEvent.tapEnable(tap: sessionTap, enable: active)
            applied = active
        }
    }

    private func createTaps() -> Bool {
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let modifier = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                Unmanaged<InputTaps>.fromOpaque(userInfo).takeUnretainedValue().handleModifier(type, event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )
        let session = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let swallow = Unmanaged<InputTaps>.fromOpaque(userInfo).takeUnretainedValue().handleSessionKey(type, event)
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )
        guard let modifier, let session else {
            [modifier, session].compactMap { $0 }.forEach(CFMachPortInvalidate)
            return false
        }
        let runLoop = CFRunLoopGetCurrent()
        for tap in [modifier, session] {
            CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        }
        state.withLockUnchecked { state in
            state.modifierTap = modifier
            state.sessionTap = session
            state.runLoop = runLoop
        }
        // Taps recreated during a session start armed.
        follow(session, enabled: nil)
        return true
    }

    private func handleModifier(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let modifierTap = state.withLock({ $0.modifierTap.map(UncheckedPort.init) }) {
                CGEvent.tapEnable(tap: modifierTap.port, enable: true)
            }
            return
        }
        guard !event.flags.contains(.maskCommand), state.withLock({ $0.sessionActive }) else { return }
        onCommandReleased(Self.nanoseconds(event.timestamp))
    }

    /// Read as mach ticks rather than the nanoseconds CGEventTimestamp is documented as, which differ on
    /// Apple silicon. A wrong reading fails the plausibility check on main, and then no late Tab is dropped.
    private static func nanoseconds(_ ticks: CGEventTimestamp) -> UInt64 {
        let (product, overflow) = ticks.multipliedReportingOverflow(by: UInt64(timebase.numer))
        return overflow || timebase.denom == 0 ? 0 : product / UInt64(timebase.denom)
    }

    private func handleSessionKey(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let sessionTap = state.withLock({ $0.sessionTap.map(UncheckedPort.init) }) { follow(sessionTap.port, enabled: false) }
            return false
        }
        guard type == .keyDown, event.flags.contains(.maskCommand), state.withLock({ $0.sessionActive }) else { return false }
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keycode != KeyCode.tab else { return false } // Tab belongs to the Carbon hotkeys.
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        let key = SessionKey(keycode: keycode, characters: String(utf16CodeUnits: buffer, count: length))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        // Every other Cmd+key is swallowed too: the previous app is still key, and Cmd+W would otherwise
        // reach it while the switcher is open.
        if let key, key.repeats || !isRepeat { onSessionKey(key) }
        return true
    }
}
