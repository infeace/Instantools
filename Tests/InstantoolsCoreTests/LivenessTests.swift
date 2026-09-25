import Testing
@testable import InstantoolsCore

struct LivenessTests {
    private func checks(_ count: Int, _ liveness: inout Liveness) -> [Liveness.Action] {
        (0..<count).map { _ in liveness.check() }
    }

    @Test func aToolThatNeverBecomesReadyIsStoppedAfterTheLaunchLimit() {
        var liveness = Liveness()
        #expect(checks(Liveness.launchLimit - 1, &liveness).allSatisfy { $0 == .wait })
        #expect(liveness.check() == .stop)
    }

    @Test func aToolThatAnswersIsPingedForever() {
        var liveness = Liveness()
        liveness.heard(ToolMessage(event: .ready))
        let actions = (0..<100).map { _ in
            defer { liveness.heard(ToolMessage(event: .pong)) }
            return liveness.check()
        }
        #expect(actions.allSatisfy { $0 == .ping })
    }

    @Test func aToolThatStopsAnsweringIsStoppedAfterTheReplyLimit() {
        var liveness = Liveness()
        liveness.heard(ToolMessage(event: .ready))
        #expect(checks(Liveness.replyLimit - 1, &liveness).allSatisfy { $0 == .ping })
        #expect(liveness.check() == .stop)
    }

    @Test func anyMessageCountsAsAnAnswer() {
        var liveness = Liveness()
        liveness.heard(ToolMessage(event: .ready))
        _ = checks(Liveness.replyLimit - 1, &liveness)
        liveness.heard(ToolMessage(layoutSwitcher: LayoutSwitcherStatus(tapRunning: true)))
        #expect(checks(Liveness.replyLimit - 1, &liveness).allSatisfy { $0 == .ping })
    }

    /// A tool that was nearly hung when the Mac woke gets the whole grace, then the full limit again.
    @Test func aWakeStartsTheCountOverAfterAGrace() {
        var liveness = Liveness()
        liveness.heard(ToolMessage(event: .ready))
        _ = checks(Liveness.replyLimit - 1, &liveness)
        liveness.woke()
        #expect(checks(Liveness.wakeGrace + Liveness.replyLimit - 1, &liveness).allSatisfy { $0 == .ping })
        #expect(liveness.check() == .stop)
    }

    @Test func aWakeDuringLaunchWaitsLonger() {
        var liveness = Liveness()
        _ = checks(Liveness.launchLimit - 1, &liveness)
        liveness.woke()
        #expect(checks(Liveness.wakeGrace + Liveness.launchLimit - 1, &liveness).allSatisfy { $0 == .wait })
        #expect(liveness.check() == .stop)
    }
}
