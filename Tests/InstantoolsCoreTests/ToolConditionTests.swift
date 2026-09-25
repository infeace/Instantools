import Testing
@testable import InstantoolsCore

struct ToolConditionTests {
    @Test func aFailureShowsWhetherOrNotTheToolIsOn() {
        #expect(ToolCondition(enabled: true, state: .failed("gone"), isActive: false) == .failed("gone"))
        #expect(ToolCondition(enabled: false, state: .failed("gone"), isActive: false) == .failed("gone"))
    }

    @Test func aToolTurnedOffIsOffWhileItStillStops() {
        #expect(ToolCondition(enabled: false, state: .running, isActive: true) == .off)
        #expect(ToolCondition(enabled: false, state: .off, isActive: false) == .off)
    }

    @Test func aToolThatIsOnIsStartingUntilItRuns() {
        #expect(ToolCondition(enabled: true, state: .off, isActive: false) == .starting)
        #expect(ToolCondition(enabled: true, state: .starting, isActive: false) == .starting)
    }

    @Test func aRunningToolIsActiveOnlyWhileItDoesItsJob() {
        #expect(ToolCondition(enabled: true, state: .running, isActive: true) == .active)
        #expect(ToolCondition(enabled: true, state: .running, isActive: false) == .inactive)
    }

    @Test func cmdTabIsActiveUnlessMacOSKeptIt() {
        let isActive = { (state: ToolState, handles: Bool?) in
            ToolCondition.isActive(.appSwitcher, state: state, handlesCmdTab: handles, tapRunning: nil, inputMonitoring: { false })
        }
        #expect(isActive(.running, nil))
        #expect(isActive(.running, true))
        #expect(!isActive(.running, false))
        #expect(!isActive(.starting, true))
    }

    @Test func languageNeedsItsTapAndInputMonitoring() {
        let isActive = { (tap: Bool?, inputMonitoring: Bool) in
            ToolCondition.isActive(.layoutSwitcher, state: .running, handlesCmdTab: false, tapRunning: tap, inputMonitoring: { inputMonitoring })
        }
        #expect(isActive(nil, true))
        #expect(isActive(true, true))
        #expect(!isActive(true, false))
        #expect(!isActive(false, true))
    }

    @Test func theInputMonitoringCheckIsMadeOnlyWhenItDecides() {
        var checks = 0
        let check = { checks += 1; return true }
        _ = ToolCondition.isActive(.layoutSwitcher, state: .starting, handlesCmdTab: nil, tapRunning: true, inputMonitoring: check)
        _ = ToolCondition.isActive(.layoutSwitcher, state: .running, handlesCmdTab: nil, tapRunning: false, inputMonitoring: check)
        _ = ToolCondition.isActive(.appSwitcher, state: .running, handlesCmdTab: nil, tapRunning: nil, inputMonitoring: check)
        #expect(checks == 0)
        _ = ToolCondition.isActive(.layoutSwitcher, state: .running, handlesCmdTab: nil, tapRunning: true, inputMonitoring: check)
        #expect(checks == 1)
    }
}

struct FlowRowsTests {
    @Test func itemsThatFitShareARow() {
        #expect(FlowRows.rows(widths: [40, 40, 40], maxWidth: 140, spacing: 10) == [0..<3])
    }

    @Test func wrapsWhenTheSpacingNoLongerFits() {
        #expect(FlowRows.rows(widths: [40, 40, 40], maxWidth: 139, spacing: 10) == [0..<2, 2..<3])
        #expect(FlowRows.rows(widths: [50, 50, 50, 50, 50], maxWidth: 110, spacing: 10) == [0..<2, 2..<4, 4..<5])
    }

    @Test func anItemWiderThanARowGetsItsOwn() {
        #expect(FlowRows.rows(widths: [30, 200, 30], maxWidth: 100, spacing: 10) == [0..<1, 1..<2, 2..<3])
        #expect(FlowRows.rows(widths: [200], maxWidth: 100, spacing: 10) == [0..<1])
    }

    @Test func nothingMakesNoRows() {
        #expect(FlowRows.rows(widths: [], maxWidth: 100, spacing: 10).isEmpty)
    }
}
