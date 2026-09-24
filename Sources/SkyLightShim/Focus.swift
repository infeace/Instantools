import ApplicationServices

extension SkyLight {
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessWithOptions =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordTo = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias AXUIElementGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getProcessForPID = symbol("GetProcessForPID", as: GetProcessForPID.self)
    private static let setFrontProcessWithOptions =
        symbol("_SLPSSetFrontProcessWithOptions", as: SetFrontProcessWithOptions.self)
    private static let postEventRecordTo = symbol("SLPSPostEventRecordTo", as: PostEventRecordTo.self)
    private static let axUIElementGetWindow = symbol("_AXUIElementGetWindow", as: AXUIElementGetWindow.self)

    /// Marks the switch as user initiated so WindowServer does not suppress it.
    private static let userGenerated: UInt32 = 0x200

    public static var canFocusWindows: Bool {
        getProcessForPID != nil && setFrontProcessWithOptions != nil && postEventRecordTo != nil
    }

    /// Makes `pid` the front process with `windowId` (0 for none) as its front window, then makes that
    /// window key. No public API moves focus across apps; this is the yabai and AltTab recipe.
    @discardableResult
    public static func focus(pid: pid_t, windowId: CGWindowID) -> Bool {
        guard let getProcessForPID, let setFrontProcessWithOptions else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        guard setFrontProcessWithOptions(&psn, windowId, userGenerated) == .success else { return false }
        if windowId != 0 { makeKeyWindow(&psn, windowId) }
        return true
    }

    /// A synthetic click, mouse-down then mouse-up (layout from CGSInternal's CGSEvent.h), aimed far past the
    /// window so nothing is clicked. The buffer is 0x100 bytes for a 0xf8 record because WindowServer reads
    /// past it since 14.7.4.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowId: CGWindowID) {
        guard let postEventRecordTo else { return }
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8 // record length
        bytes[0x08] = 0x01 // kCGEventLeftMouseDown
        bytes[0x3a] = 0x10 // undocumented, set by yabai and Hammerspoon
        var point = CGPoint(x: 300_000, y: 300_000)
        var id = windowId
        withUnsafeBytes(of: &point) { bytes.replaceSubrange(0x20..<0x30, with: $0) }
        withUnsafeBytes(of: &id) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        _ = bytes.withUnsafeMutableBufferPointer { postEventRecordTo(&psn, $0.baseAddress!) }
        bytes[0x08] = 0x02 // kCGEventLeftMouseUp, or the app is left thinking the button is down
        _ = bytes.withUnsafeMutableBufferPointer { postEventRecordTo(&psn, $0.baseAddress!) }
    }

    public static func windowId(of element: AXUIElement) -> CGWindowID? {
        guard let axUIElementGetWindow else { return nil }
        var id: CGWindowID = 0
        return axUIElementGetWindow(element, &id) == .success ? id : nil
    }
}
