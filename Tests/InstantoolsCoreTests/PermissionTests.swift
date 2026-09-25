import Testing
@testable import InstantoolsCore

struct PermissionTests {
    private let none = PermissionState(accessibility: false, inputMonitoring: false)
    private let accessibility = PermissionState(accessibility: true, inputMonitoring: true)
    private let inputMonitoringOnly = PermissionState(accessibility: false, inputMonitoring: true)
    private let switchedOff = PermissionState(accessibility: true, inputMonitoring: false)
    private let both: Set<ToolId> = [.appSwitcher, .layoutSwitcher]

    @Test func inputMonitoringIsSwitchedOffOnlyWhenItFailsWithAccessibilityOn() {
        #expect(switchedOff.inputMonitoringSwitchedOff)
        #expect(!none.inputMonitoringSwitchedOff)
        #expect(!accessibility.inputMonitoringSwitchedOff)
        #expect(!inputMonitoringOnly.inputMonitoringSwitchedOff)
    }

    @Test func cmdTabLacksInputMonitoringOnlyOnceItWasSwitchedOff() {
        #expect(none.missing(for: .appSwitcher) == [.accessibility])
        #expect(inputMonitoringOnly.missing(for: .appSwitcher) == [.accessibility])
        #expect(accessibility.missing(for: .appSwitcher).isEmpty)
        #expect(switchedOff.missing(for: .appSwitcher) == [.inputMonitoring])
    }

    @Test func languageLacksOnlyInputMonitoring() {
        #expect(none.missing(for: .layoutSwitcher) == [.inputMonitoring])
        #expect(switchedOff.missing(for: .layoutSwitcher) == [.inputMonitoring])
        #expect(accessibility.missing(for: .layoutSwitcher).isEmpty)
        #expect(inputMonitoringOnly.missing(for: .layoutSwitcher).isEmpty)
    }

    @Test func noToolNeedsNothing() {
        for state in [none, accessibility, inputMonitoringOnly, switchedOff] {
            #expect(state.needed(by: []).isEmpty)
        }
    }

    @Test func cmdTabAlwaysShowsAccessibilityGrantedOrNot() {
        #expect(none.needed(by: [.appSwitcher]) == [PermissionNeed(.accessibility, for: .appSwitcher)])
        #expect(accessibility.needed(by: [.appSwitcher]) == [PermissionNeed(.accessibility, for: .appSwitcher)])
        #expect(inputMonitoringOnly.needed(by: [.appSwitcher]) == [PermissionNeed(.accessibility, for: .appSwitcher)])
    }

    @Test func cmdTabAloneShowsInputMonitoringOnlyWhenSwitchedOff() {
        #expect(switchedOff.needed(by: [.appSwitcher]) == [
            PermissionNeed(.accessibility, for: .appSwitcher), PermissionNeed(.inputMonitoring, for: .appSwitcher),
        ])
    }

    @Test func languageShowsInputMonitoringUntilAccessibilityCoversIt() {
        #expect(none.needed(by: [.layoutSwitcher]) == [PermissionNeed(.inputMonitoring, for: .layoutSwitcher)])
        #expect(inputMonitoringOnly.needed(by: [.layoutSwitcher]) == [PermissionNeed(.inputMonitoring, for: .layoutSwitcher)])
        #expect(switchedOff.needed(by: [.layoutSwitcher]) == [PermissionNeed(.inputMonitoring, for: .layoutSwitcher)])
        #expect(accessibility.needed(by: [.layoutSwitcher]).isEmpty)
    }

    @Test func bothToolsShowInputMonitoringOnceExplainedByLanguage() {
        let accessibilityRow = PermissionNeed(.accessibility, for: .appSwitcher)
        let inputMonitoringRow = PermissionNeed(.inputMonitoring, for: .layoutSwitcher)
        #expect(none.needed(by: both) == [accessibilityRow, inputMonitoringRow])
        #expect(inputMonitoringOnly.needed(by: both) == [accessibilityRow, inputMonitoringRow])
        #expect(switchedOff.needed(by: both) == [accessibilityRow, inputMonitoringRow])
        #expect(accessibility.needed(by: both) == [accessibilityRow])
    }

    @Test func eachNeedReportsItsOwnStatus() {
        #expect(inputMonitoringOnly.isGranted(.inputMonitoring))
        #expect(!inputMonitoringOnly.isGranted(.accessibility))
        #expect(switchedOff.isGranted(.accessibility))
        #expect(!switchedOff.isGranted(.inputMonitoring))
    }
}

struct WelcomeStepTests {
    @Test func goesThroughEveryStepWithAToolChosen() {
        for tools: Set<ToolId> in [[.appSwitcher], [.layoutSwitcher], [.appSwitcher, .layoutSwitcher]] {
            #expect(WelcomeStep.tools.next(choosing: tools) == .permissions)
            #expect(WelcomeStep.permissions.next(choosing: tools) == .done)
            #expect(WelcomeStep.done.next(choosing: tools) == nil)
            #expect(WelcomeStep.done.previous(choosing: tools) == .permissions)
            #expect(WelcomeStep.permissions.previous(choosing: tools) == .tools)
            #expect(WelcomeStep.tools.previous(choosing: tools) == nil)
        }
    }

    @Test func choosingNoToolSkipsPermissionsBothWays() {
        #expect(WelcomeStep.permissions.isSkipped(choosing: []))
        #expect(!WelcomeStep.permissions.isSkipped(choosing: [.layoutSwitcher]))
        #expect(WelcomeStep.tools.next(choosing: []) == .done)
        #expect(WelcomeStep.done.previous(choosing: []) == .tools)
    }
}
