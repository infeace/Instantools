import AppKit
import AppSwitcherCore

@MainActor
public final class Displays {
    public private(set) var displays: [Display] = []
    private var screensById: [UInt32: NSScreen] = [:]
    public var onChange: (() -> Void)?

    public init() {}

    public func start() {
        reload()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
                self?.onChange?()
            }
        }
    }

    private func reload() {
        var list: [Display] = []
        var byId: [UInt32: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayId else { continue }
            list.append(Display(
                id: id, frame: CGDisplayBounds(id), uuid: Self.uuid(of: id), name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0
            ))
            byId[id] = screen
        }
        displays = list
        screensById = byId
    }

    private static func uuid(of id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    public func mouseDisplayId() -> UInt32? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
        return screen?.displayId
    }

    public func screen(for id: UInt32?) -> NSScreen? {
        id.flatMap { screensById[$0] } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

extension NSScreen {
    public var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
