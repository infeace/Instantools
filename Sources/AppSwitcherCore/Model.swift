import CoreGraphics

public struct RunningApp: Sendable, Equatable {
    public var pid: Int32
    public var bundleId: String?
    public var name: String
    public var isHidden: Bool

    public init(pid: Int32, bundleId: String?, name: String, isHidden: Bool = false) {
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.isHidden = isHidden
    }
}

/// An on-screen, normal-level window in CoreGraphics global coordinates (top-left origin).
public struct WindowRecord: Sendable, Equatable {
    public var id: UInt32
    public var pid: Int32
    public var frame: CGRect

    public init(id: UInt32, pid: Int32, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.frame = frame
    }
}

/// A display in CoreGraphics global coordinates (top-left origin).
public struct Display: Sendable, Equatable {
    public var id: UInt32
    public var frame: CGRect
    /// Stable across reconnects, except between identical monitors.
    public var uuid: String
    public var name: String
    public var isBuiltIn: Bool
    /// Has the menu bar.
    public var isMain: Bool

    public init(id: UInt32, frame: CGRect, uuid: String = "", name: String = "", isBuiltIn: Bool = false, isMain: Bool = false) {
        self.id = id
        self.frame = frame
        self.uuid = uuid
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
    }
}

/// Everything the switcher needs at key press, kept fresh by the tracker so reading it costs no IPC.
public struct Snapshot: Sendable, Equatable {
    /// Most recently used first.
    public var apps: [RunningApp]
    /// Front to back.
    public var windows: [WindowRecord]
    public var lastDisplayByPid: [Int32: UInt32]

    public init(apps: [RunningApp] = [], windows: [WindowRecord] = [], lastDisplayByPid: [Int32: UInt32] = [:]) {
        self.apps = apps
        self.windows = windows
        self.lastDisplayByPid = lastDisplayByPid
    }
}

/// One tile in the switcher. `windowId` is the window to focus, or nil to activate the app.
public struct SwitcherEntry: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    public var windowId: UInt32?
    /// The app key bound to this app, shown on its tile.
    public var key: Character?
    public var isHidden: Bool

    public init(pid: Int32, name: String, windowId: UInt32?, key: Character? = nil, isHidden: Bool = false) {
        self.pid = pid
        self.name = name
        self.windowId = windowId
        self.key = key
        self.isHidden = isHidden
    }

    /// Shown after the selected app's name, and dims its tile, when switching to it finds no window
    /// already on screen.
    public var state: String? {
        Self.state(isHidden: isHidden, hasWindow: windowId != nil)
    }

    public static func state(isHidden: Bool, hasWindow: Bool) -> String? {
        if isHidden { return "Hidden" }
        return hasWindow ? nil : "No visible window"
    }
}
