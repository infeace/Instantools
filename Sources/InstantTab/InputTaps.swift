import CoreGraphics
import Foundation
import os

/// Keys the switcher handles while it is open, besides Tab.
enum SessionKey: Sendable {
    case cancel
    case previous
    case next
}

/// Event taps on a dedicated thread, so a busy main thread never delays reading the keyboard.
/// The modifier tap is listen-only and always on. The session tap swallows keys, so it is only
/// enabled while the switcher is open (an always-on filtering tap can break input methods). It sits
/// at the HID level so it sees Cmd+Esc before system shortcuts such as Game Overlay do.
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

    var hasModifierTap: Bool { modifierTap != nil }

    /// Creates the taps on their own thread. Returns false when macOS refused (no permission yet).
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
        modifierTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                Unmanaged<InputTaps>.fromOpaque(userInfo).takeUnretainedValue().handleModifier(type, event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )
        sessionTap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let swallow = Unmanaged<InputTaps>.fromOpaque(userInfo).takeUnretainedValue().handleSessionKey(type, event)
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )
        if modifierTap == nil, let sessionTap {
            CFMachPortInvalidate(sessionTap)
            self.sessionTap = nil
        }
        for tap in [modifierTap, sessionTap].compactMap({ $0 }) {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let sessionTap { CGEvent.tapEnable(tap: sessionTap, enable: false) }
    }

    // Tap callbacks: integer compares and a queued handoff only, never IPC.

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
        guard keycode != 48 else { return false } // Tab belongs to the Carbon hotkeys
        let key: SessionKey? = switch keycode {
        case 53: .cancel // Escape
        case 123: .previous // Left arrow
        case 124: .next // Right arrow
        default: nil
        }
        // Every other Cmd+key is swallowed too: the previous app is still key, and Cmd+Q or Cmd+W
        // would otherwise reach it while the switcher is open.
        if let key { onSessionKey(key) }
        return true
    }
}
