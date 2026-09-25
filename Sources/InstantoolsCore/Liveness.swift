/// Tells a hung tool from a busy one. The host checks each tool every `interval` seconds: until the tool is
/// ready it only waits, and after that each check pings it. Any message from the tool counts as an answer.
/// Checks are counted rather than timed, since the host's timer does not run while the Mac sleeps and checks
/// that fall due while the host itself is busy run once. Neither then reads as a tool that stopped answering.
public struct Liveness: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case wait
        case ping
        /// The tool is hung, and is stopped and restarted like one that crashed.
        case stop
    }

    public static let interval = 2.0
    /// Checks in a row without a message: 12 seconds to become ready, and once it is, 6 to 8 seconds without
    /// an answer. Accessibility calls in InstantTab time out after half a second, so a busy tool answers well
    /// within that.
    public static let launchLimit = 6
    public static let replyLimit = 4
    /// Checks that do not count after a wake, which can stall a tool for a second or two.
    public static let wakeGrace = 5

    public private(set) var isReady = false
    private var silentChecks = 0
    private var grace = 0

    public init() {}

    public mutating func check() -> Action {
        if grace > 0 { grace -= 1 } else { silentChecks += 1 }
        if !isReady { return silentChecks >= Self.launchLimit ? .stop : .wait }
        return silentChecks >= Self.replyLimit ? .stop : .ping
    }

    public mutating func heard(_ message: ToolMessage) {
        if message.event == .ready { isReady = true }
        silentChecks = 0
    }

    /// After the Mac or its screens wake, or the user's session becomes active again.
    public mutating func woke() {
        silentChecks = 0
        grace = Self.wakeGrace
    }
}
