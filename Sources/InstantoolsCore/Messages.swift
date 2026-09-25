import Foundation

/// Host to tool, one JSON object per line on the tool's stdin, such as `{"id":1,"request":"status"}`.
public struct HostRequest: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case status
    }

    public var id: Int
    public var request: Kind

    public init(id: Int, request: Kind) {
        self.id = id
        self.request = request
    }
}

public enum ToolEvent: String, Codable, Sendable {
    case ready
}

/// Tool to host, one JSON object per line on the tool's stdout: a reply carries the request's id and the
/// tool's status, an event carries no id.
public struct ToolMessage: Codable, Equatable, Sendable {
    public var id: Int?
    public var event: ToolEvent?
    public var appSwitcher: AppSwitcherStatus?
    public var layoutSwitcher: LayoutSwitcherStatus?

    public init(id: Int? = nil, event: ToolEvent? = nil, appSwitcher: AppSwitcherStatus? = nil, layoutSwitcher: LayoutSwitcherStatus? = nil) {
        self.id = id
        self.event = event
        self.appSwitcher = appSwitcher
        self.layoutSwitcher = layoutSwitcher
    }
}

public struct AppSwitcherStatus: Codable, Equatable, Sendable {
    /// What Cmd+Tab would list from every display, for the Settings preview.
    public struct RecentApp: Codable, Equatable, Sendable {
        public var pid: Int32
        public var name: String
        public var hasWindow: Bool
        public var isHidden: Bool
        /// The app key bound to it, as a one-character string.
        public var key: String?

        public init(pid: Int32, name: String, hasWindow: Bool, isHidden: Bool = false, key: String? = nil) {
            self.pid = pid
            self.name = name
            self.hasWindow = hasWindow
            self.isHidden = isHidden
            self.key = key
        }
    }

    /// Key press to first frame, oldest first, in nanoseconds.
    public var latencySamples: [UInt64]
    /// The display of the frontmost app's window, as Cmd+Tab sees it.
    public var focusedDisplay: UInt32?
    /// Most recently used first, without excluded apps.
    public var recentApps: [RecentApp]
    public var tapsRunning: Bool
    /// False when macOS kept its own Cmd+Tab, because the hotkeys could not be registered or it would not turn off.
    public var handlesCmdTab: Bool

    public init(latencySamples: [UInt64] = [], focusedDisplay: UInt32? = nil, recentApps: [RecentApp] = [], tapsRunning: Bool = false, handlesCmdTab: Bool = false) {
        self.latencySamples = latencySamples
        self.focusedDisplay = focusedDisplay
        self.recentApps = recentApps
        self.tapsRunning = tapsRunning
        self.handlesCmdTab = handlesCmdTab
    }
}

public struct LayoutSwitcherStatus: Codable, Equatable, Sendable {
    public var tapRunning: Bool
    /// Display names of the layouts Control+Command switches between.
    public var layouts: [String]

    public init(tapRunning: Bool = false, layouts: [String] = []) {
        self.tapRunning = tapRunning
        self.layouts = layouts
    }
}

public enum MessageCoding {
    /// JSON on one line. JSONEncoder escapes newlines inside strings, so the line ending is the only one.
    public static func line(_ value: some Encodable) -> Data? {
        guard var data = try? JSONEncoder().encode(value) else { return nil }
        data.append(0x0A)
        return data
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from line: [UInt8]) -> Value? {
        try? JSONDecoder().decode(type, from: Data(line))
    }
}

/// Splits a byte stream into lines, keeping a partial line until the rest arrives.
public struct LineBuffer: Sendable {
    /// Anything longer is not a message, so it is dropped rather than kept growing.
    public static let maxLineLength = 1 << 20

    private var pending: [UInt8] = []
    private var discarding = false

    public init() {}

    public mutating func append(_ bytes: some Sequence<UInt8>) -> [[UInt8]] {
        var lines: [[UInt8]] = []
        for byte in bytes {
            if byte == 0x0A {
                if !discarding, !pending.isEmpty { lines.append(pending) }
                pending.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                pending.append(byte)
                if pending.count > Self.maxLineLength {
                    pending.removeAll()
                    discarding = true
                }
            }
        }
        return lines
    }
}
