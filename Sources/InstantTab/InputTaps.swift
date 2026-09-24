import CoreGraphics
import Foundation
import InstantTabCore
import os

/// On their own thread so a busy main thread never delays the keyboard. The session tap swallows keys, so
/// it is on only while the switcher is open (always on, it breaks input methods), and sits at the HID
/// level to see Cmd+Esc before Game Overlay does.
final class InputTaps: @unchecked Sendable {
    private let onCommandReleased: @Sendable () -> Void
    private let onSessionKey: @Sendable (SessionKey) -> Void
    private let sessionActive = OSAllocatedUnfairLock(initialState: false)
    private var modifierTap: CFMachPort?
    private var sessionTap: CFMachPort?

    init(onCommandReleased: @escaping @Sendable () -> Void, onSessionKey: @escaping @Sendable (SessionKey) -> Void) {
        self.onCommandReleased = onCommandReleased
        self.onSessionKey = onSessionKey
    }

    /// False until macOS allows both taps, so callers can retry once Accessibility is granted.
    func start() -> Bool {
        guard modifierTap == nil else { return true }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            createTaps()
            ready.signal()
            guard modifierTap != nil else { return }
            CFRunLoopRun()
        }
        thread.name = "com.infeace.InstantTab.input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return modifierTap != nil
    }

    func setSessionActive(_ active: Bool) {
        sessionActive.withLock { $0 = active }
        if let sessionTap { CGEvent.tapEnable(tap: sessionTap, enable: active) }
    }

    private func createTaps() {
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
            return
        }
        for tap in [modifier, session] {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        }
        CGEvent.tapEnable(tap: session, enable: false)
        modifierTap = modifier
        sessionTap = session
    }

    private func handleModifier(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let modifierTap { CGEvent.tapEnable(tap: modifierTap, enable: true) }
            return
        }
        guard !event.flags.contains(.maskCommand), sessionActive.withLock({ $0 }) else { return }
        onCommandReleased()
    }

    private func handleSessionKey(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let sessionTap, sessionActive.withLock({ $0 }) { CGEvent.tapEnable(tap: sessionTap, enable: true) }
            return false
        }
        guard type == .keyDown, event.flags.contains(.maskCommand), sessionActive.withLock({ $0 }) else { return false }
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
