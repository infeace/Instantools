import Foundation

/// Host to tool, one JSON object per line on the tool's stdin, such as `{"request":"status"}`.
public struct HostRequest: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case status
    }

    public var request: Kind

    public init(request: Kind) {
        self.request = request
    }
}

public enum ToolEvent: String, Codable, Sendable {
    case ready
}

/// Tool to host, one JSON object per line on the tool's stdout: an event, or a reply with the tool's status.
public struct ToolMessage: Codable, Equatable, Sendable {
    public var event: ToolEvent?
    public var appSwitcher: AppSwitcherStatus?
    public var layoutSwitcher: LayoutSwitcherStatus?

    public init(event: ToolEvent? = nil, appSwitcher: AppSwitcherStatus? = nil, layoutSwitcher: LayoutSwitcherStatus? = nil) {
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

        public init(pid: Int32, name: String) {
            self.pid = pid
            self.name = name
        }
    }

    /// Key press to the display frame the panel is drawn for, oldest first, in nanoseconds.
    public var latencySamples: [UInt64]
    /// The display of the frontmost app's window, as Cmd+Tab sees it.
    public var focusedDisplay: UInt32?
    /// Most recently used first, without excluded apps.
    public var recentApps: [RecentApp]
    /// False when macOS kept its own Cmd+Tab, because the hotkeys could not be registered or it would not turn off.
    public var handlesCmdTab: Bool

    public init(latencySamples: [UInt64] = [], focusedDisplay: UInt32? = nil, recentApps: [RecentApp] = [], handlesCmdTab: Bool = false) {
        self.latencySamples = latencySamples
        self.focusedDisplay = focusedDisplay
        self.recentApps = recentApps
        self.handlesCmdTab = handlesCmdTab
    }
}

/// The layouts are not part of it: the host reads them itself.
public struct LayoutSwitcherStatus: Codable, Equatable, Sendable {
    public var tapRunning: Bool

    public init(tapRunning: Bool = false) {
        self.tapRunning = tapRunning
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
