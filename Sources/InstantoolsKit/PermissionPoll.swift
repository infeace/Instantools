import Foundation

/// For starting what waits on a permission granted in System Settings. The check runs off the main thread,
/// since the Input Monitoring one takes 10 ms or more and a key press arriving meanwhile would wait.
@MainActor
public final class PermissionPoll {
    private let allowed: @Sendable () -> Bool
    private let start: @MainActor () -> Bool
    private let success: String
    private var timer: Timer?
    private var checking = false

    public init(allowed: @escaping @Sendable () -> Bool, start: @escaping @MainActor () -> Bool, thenLog success: String) {
        self.allowed = allowed
        self.start = start
        self.success = success
    }

    public var isPolling: Bool { timer != nil }

    /// Tries every second until `start` succeeds once `allowed`. Asking again while it polls changes nothing.
    public func run() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.attempt() }
        }
    }

    /// Runs `check` off the main thread and hands its answer to `then` on main.
    public static func check<Answer: Sendable>(
        _ check: @escaping @Sendable () -> Answer, then: @escaping @MainActor @Sendable (Answer) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let answer = check()
            DispatchQueue.main.async { MainActor.assumeIsolated { then(answer) } }
        }
    }

    /// A check can outlast the timer's interval, so a slow one is not overlapped by the next.
    private func attempt() {
        guard !checking else { return }
        checking = true
        Self.check(allowed) { [weak self] granted in
            guard let self else { return }
            checking = false
            guard granted, timer != nil, start() else { return }
            timer?.invalidate()
            timer = nil
            Diagnostics.log.notice("\(self.success, privacy: .public)")
        }
    }
}
