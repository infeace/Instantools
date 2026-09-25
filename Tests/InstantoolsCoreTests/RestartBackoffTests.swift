import Testing
@testable import InstantoolsCore

struct RestartBackoffTests {
    @Test func restartsAtOnceThenBacksOff() {
        var backoff = RestartBackoff()
        #expect(backoff.exited(at: 100) == .restart(afterSeconds: 0))
        #expect(backoff.exited(at: 101) == .restart(afterSeconds: 1))
        #expect(backoff.exited(at: 103) == .restart(afterSeconds: 5))
        #expect(backoff.exited(at: 109) == .restart(afterSeconds: 5))
    }

    @Test func givesUpAfterFiveExitsWithinAMinute() {
        var backoff = RestartBackoff()
        for time in [0.0, 1, 7, 13] { _ = backoff.exited(at: time) }
        #expect(backoff.exited(at: 59) == .giveUp)
    }

    @Test func exitsOlderThanAMinuteAreForgotten() {
        var backoff = RestartBackoff()
        for time in [0.0, 1, 7, 13] { _ = backoff.exited(at: time) }
        // Only the exits at 13 and 70 are within the last minute.
        #expect(backoff.exited(at: 70) == .restart(afterSeconds: 1))
        #expect(backoff.exits == [13, 70])
    }

    @Test func aToolThatRanForAMinuteStartsOverAtOnce() {
        var backoff = RestartBackoff()
        _ = backoff.exited(at: 0)
        _ = backoff.exited(at: 1)
        #expect(backoff.exited(at: 200) == .restart(afterSeconds: 0))
    }

    @Test func resetStartsOver() {
        var backoff = RestartBackoff()
        for time in [0.0, 1, 2, 3] { _ = backoff.exited(at: time) }
        backoff.reset()
        #expect(backoff.exited(at: 4) == .restart(afterSeconds: 0))
    }
}
