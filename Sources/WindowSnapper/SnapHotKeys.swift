import Carbon.HIToolbox
import InstantoolsKit
import WindowSnapperCore

/// Carbon hotkeys need no permission and keep working under Secure Input, like InstantTab's Cmd+Tab. They
/// are registered exclusively: macOS refuses one another app already has, which is how a taken shortcut is
/// found, and an app registering one later gets no presses of it while InstantSnap holds it.
@MainActor
final class SnapHotKeys {
    var onPress: ((SnapAction) -> Void)?
    /// The shortcuts another app, such as Rectangle, already has.
    private(set) var unavailable: [Shortcut] = []

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: SnapAction] = [:]
    private var registered: [SnapAction: Shortcut] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x494E_534E // "INSN"

    /// Replaces every shortcut, and does nothing when they are the same as before.
    func register(_ bindings: [(action: SnapAction, shortcut: Shortcut)]) {
        let wanted = Dictionary(uniqueKeysWithValues: bindings.map { ($0.action, $0.shortcut) })
        guard wanted != registered || refs.isEmpty && !wanted.isEmpty else { return }
        unregister()
        registered = wanted
        if handler == nil, !installHandler() {
            Diagnostics.log.error("could not install the hotkey handler")
            unavailable = bindings.map(\.shortcut)
            return
        }
        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.shortcut.keyCode), Self.carbonModifiers(binding.shortcut.modifiers),
                EventHotKeyID(signature: Self.signature, id: id), GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = binding.action
            } else {
                Diagnostics.log.error("RegisterEventHotKey failed for \(binding.shortcut.text, privacy: .public): \(status)")
                unavailable.append(binding.shortcut)
            }
        }
    }

    func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
        registered.removeAll()
        unavailable.removeAll()
    }

    private static func carbonModifiers(_ modifiers: Shortcut.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
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
                guard status == noErr, id.signature == SnapHotKeys.signature else { return OSStatus(eventNotHandledErr) }
                let hotKeys = Unmanaged<SnapHotKeys>.fromOpaque(userData).takeUnretainedValue()
                let number = id.id
                return MainActor.assumeIsolated {
                    guard let action = hotKeys.actions[number] else { return OSStatus(eventNotHandledErr) }
                    hotKeys.onPress?(action)
                    return noErr
                }
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        return status == noErr
    }
}
