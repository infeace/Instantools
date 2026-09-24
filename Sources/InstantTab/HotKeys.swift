import Carbon.HIToolbox

/// Carbon hotkeys for Cmd+Tab and Cmd+Shift+Tab. They need no permission, keep working under Secure
/// Input, and win over the frontmost app once the native symbolic hotkeys are off.
@MainActor
final class HotKeys {
    enum Action: UInt32 {
        case forward = 1
        case backward = 2
    }

    /// Receives the action and the key event's time in nanoseconds of uptime.
    var onPress: ((Action, UInt64) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x494E_5442 // "INTB"

    var isRegistered: Bool { !refs.isEmpty }

    func register() -> Bool {
        guard refs.isEmpty else { return true }
        if handler == nil, !installHandler() { return false }
        let bindings: [(Action, UInt32)] = [(.forward, UInt32(cmdKey)), (.backward, UInt32(cmdKey | shiftKey))]
        for (action, modifiers) in bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(UInt32(kVK_Tab), modifiers, id, GetEventDispatcherTarget(), 0, &ref)
            guard status == noErr, let ref else {
                Diagnostics.log.error("RegisterEventHotKey failed for \(String(describing: action), privacy: .public): \(status)")
                unregister()
                return false
            }
            refs.append(ref)
        }
        return true
    }

    func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func installHandler() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                guard status == noErr, id.signature == HotKeys.signature, let action = Action(rawValue: id.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let eventTime = UInt64(max(GetEventTime(event), 0) * 1_000_000_000)
                let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKeys.onPress?(action, eventTime) }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        return status == noErr
    }
}
