import ApplicationServices

/// Accessibility calls on other apps' windows. Each is IPC to the app and waits up to the messaging timeout
/// when it is busy, so they run only on WindowMover's queue.
enum AXWindows {
    /// The focused window of the front app, as NSWorkspace names it. Shortcuts did nothing in Chrome and
    /// Electron apps when the app came from the system-wide element, so that is only the fallback.
    static func focusedWindow(frontmost pid: pid_t?) -> (window: AXUIElement, app: AXUIElement)? {
        if let pid, let found = focusedWindow(of: AXUIElementCreateApplication(pid)) { return found }
        guard let app = element(kAXFocusedApplicationAttribute, of: AXUIElementCreateSystemWide()) else { return nil }
        var appPid: pid_t = 0
        guard AXUIElementGetPid(app, &appPid) == .success, appPid != pid else { return nil }
        return focusedWindow(of: app)
    }

    /// An app that is not answering takes the whole messaging timeout for every call, so it is asked once.
    private static func focusedWindow(of app: AXUIElement) -> (window: AXUIElement, app: AXUIElement)? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard error != .cannotComplete,
              let window = (error == .success ? asElement(value) : nil) ?? element(kAXMainWindowAttribute, of: app)
        else { return nil }
        return (window, app)
    }

    /// The window under a point, such as the one whose title bar is being dragged.
    static func window(at point: CGPoint) -> (window: AXUIElement, app: AXUIElement)? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit
        else { return nil }
        guard let window = string(kAXRoleAttribute, of: hit) == kAXWindowRole ? hit : element(kAXWindowAttribute, of: hit) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return (window, AXUIElementCreateApplication(pid))
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = value(kAXPositionAttribute, of: window), AXValueGetValue(position, .cgPoint, &origin),
              let extent = value(kAXSizeAttribute, of: window), AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func isMovable(_ window: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success && settable.boolValue
    }

    /// The frame the window ended up with, which an app can round to its own grid or clamp to its minimum.
    /// Size goes first so the window fits where it moves, and again after, since the size it could take on
    /// its old screen may have been limited.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: AXUIElement, app: AXUIElement) -> CGRect? {
        // With it on, as Chrome, Electron apps and others turn it on for assistive apps, every change animates.
        let enhanced = bool("AXEnhancedUserInterface", of: app) == true
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }
        setSize(frame.size, of: window)
        setPosition(frame.origin, of: window)
        setSize(frame.size, of: window)
        return self.frame(of: window)
    }

    static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    static func setPosition(_ origin: CGPoint, of window: AXUIElement) {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func copy(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        asElement(copy(attribute, of: element))
    }

    private static func asElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func value(_ attribute: String, of element: AXUIElement) -> AXValue? {
        guard let value = copy(attribute, of: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        copy(attribute, of: element) as? String
    }

    private static func bool(_ attribute: String, of element: AXUIElement) -> Bool? {
        guard let value = copy(attribute, of: element), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}

/// An AX window as a dictionary key. Two elements for the same window compare equal.
struct WindowRef: Hashable {
    let element: AXUIElement

    static func == (lhs: WindowRef, rhs: WindowRef) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
