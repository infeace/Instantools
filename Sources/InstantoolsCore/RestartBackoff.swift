/// When to restart a tool that exited without being asked to: at once, then after 1 second, then every 5
/// seconds. After 5 unexpected exits within a minute it stays down until someone tries again.
public struct RestartBackoff: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case restart(afterSeconds: Double)
        case giveUp
    }

    public static let delays: [Double] = [0, 1, 5]
    public static let maxExits = 5
    public static let window = 60.0

    /// Uptime in seconds of each recent unexpected exit.
    public private(set) var exits: [Double] = []

    public init() {}

    public mutating func exited(at now: Double) -> Decision {
        exits = exits.filter { now - $0 < Self.window }
        exits.append(now)
        guard exits.count < Self.maxExits else { return .giveUp }
        return .restart(afterSeconds: Self.delays[min(exits.count, Self.delays.count) - 1])
    }

    public mutating func reset() {
        exits = []
    }
}
