import Testing
@testable import InstantoolsCore

struct MigrationTests {
    @Test func freshInstallEnablesNothingAndOpensTheWelcome() {
        let plan = Migration.plan(for: .init())
        #expect(plan.enabledTools.isEmpty)
        #expect(plan.showWelcome)
        #expect(!plan.copyOldConfig)
        #expect(plan.agentsToRemove.isEmpty)
        #expect(!plan.enableStartAtLogin)
    }

    @Test func instantTabWithAgentMovesEverythingOver() {
        let plan = Migration.plan(for: .init(oldConfigExists: true, loginAgents: [.instantTab], installed: [.instantTab], running: [.instantTab]))
        #expect(plan.copyOldConfig)
        #expect(plan.agentsToRemove == [.instantTab])
        #expect(plan.enableStartAtLogin)
        #expect(plan.enabledTools == [.appSwitcher])
        #expect(!plan.showWelcome)
    }

    @Test func anExistingNewConfigIsNeverReplaced() {
        let plan = Migration.plan(for: .init(newConfigExists: true, oldConfigExists: true))
        #expect(!plan.copyOldConfig)
        #expect(plan.enabledTools == [.appSwitcher])
    }

    @Test func anyTraceOfAnOldAppEnablesItsTool() {
        #expect(Migration.plan(for: .init(oldConfigExists: true)).enabledTools == [.appSwitcher])
        #expect(Migration.plan(for: .init(running: [.instantTab])).enabledTools == [.appSwitcher])
        #expect(Migration.plan(for: .init(installed: [.instantLang])).enabledTools == [.layoutSwitcher])
        #expect(Migration.plan(for: .init(running: [.instantLang])).enabledTools == [.layoutSwitcher])
    }

    @Test func agentsRemovedByTheInstallScriptStillCount() {
        let plan = Migration.plan(for: .init(loginAgents: [.instantLang, .instantTab]))
        #expect(plan.enabledTools == [.appSwitcher, .layoutSwitcher])
        #expect(plan.agentsToRemove == [.instantTab, .instantLang])
        #expect(plan.enableStartAtLogin)
    }

    @Test func instantLangAloneDoesNotCopyTheCmdTabConfig() {
        let plan = Migration.plan(for: .init(installed: [.instantLang], running: [.instantLang]))
        #expect(!plan.copyOldConfig)
        #expect(!plan.enableStartAtLogin)
        #expect(plan.enabledTools == [.layoutSwitcher])
    }

    @Test func oldAppsMapToTheirAgentsAndTools() {
        #expect(Migration.OldApp.instantTab.agentLabel == "com.infeace.InstantTab")
        #expect(Migration.OldApp.instantLang.bundleId == "com.infeace.InstantLang")
        #expect(Migration.OldApp.instantLang.tool == .layoutSwitcher)
    }
}
