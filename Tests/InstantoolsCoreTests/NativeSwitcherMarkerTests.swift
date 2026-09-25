import Testing
@testable import InstantoolsCore

struct NativeSwitcherMarkerTests {
    @Test func quittingWhileTheSwitcherIsStillStoppingRestores() {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        marker.startingSwitcher()
        // It hangs, is turned off, and the host quits before it has exited.
        let restores = marker.quitting(switcherWasRunning: true)
        #expect(restores)
        #expect(!marker.mayBeOff)
    }

    @Test func aSwitcherThatCouldNotStartLeavesNativeCmdTabAlone() {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        marker.startingSwitcher()
        marker.switcherFailedToStart()
        // Another switcher may own the hotkeys, and quitting must not undo its setup.
        let restores = marker.quitting(switcherWasRunning: false)
        #expect(!restores)
    }

    @Test func aSwitcherStillRunningAtQuitRestoresWithoutTheMarker() {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        let restores = marker.quitting(switcherWasRunning: true)
        #expect(restores)
    }

    @Test func aLanguageOnlyLaunchLeavesNativeCmdTabAlone() {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        let atLaunch = marker.launched(stoppedLeftoverSwitcher: false)
        let atQuit = marker.quitting(switcherWasRunning: false)
        #expect(!atLaunch)
        #expect(!atQuit)
    }

    @Test func aHostCrashLeavesTheMarkerForTheNextLaunch() {
        var crashed = NativeSwitcherMarker(mayBeOff: false)
        crashed.startingSwitcher()
        var next = NativeSwitcherMarker(mayBeOff: crashed.mayBeOff)
        let first = next.launched(stoppedLeftoverSwitcher: false)
        #expect(first)
        #expect(!next.mayBeOff)
        let second = next.launched(stoppedLeftoverSwitcher: false)
        #expect(!second)
    }

    @Test func aLeftoverSwitcherStoppedAtLaunchRestores() {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        let restores = marker.launched(stoppedLeftoverSwitcher: true)
        #expect(restores)
    }

    @Test func aCleanExitClearsTheMarkerWithoutARestore() {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        marker.startingSwitcher()
        let afterExit = marker.switcherExited(asked: true, normally: true)
        #expect(!afterExit)
        #expect(!marker.mayBeOff)
        let atQuit = marker.quitting(switcherWasRunning: false)
        #expect(!atQuit)
    }

    @Test(arguments: [(false, true), (true, false), (false, false)])
    func theHostRestoresAfterAnUncleanExit(asked: Bool, normally: Bool) {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        marker.startingSwitcher()
        let restores = marker.switcherExited(asked: asked, normally: normally)
        #expect(restores)
        #expect(!marker.mayBeOff)
    }

    @Test func aRestartSetsTheMarkerAgain() {
        var marker = NativeSwitcherMarker(mayBeOff: false)
        marker.startingSwitcher()
        _ = marker.switcherExited(asked: false, normally: false)
        marker.startingSwitcher()
        #expect(marker.mayBeOff)
        let atQuit = marker.quitting(switcherWasRunning: false)
        #expect(atQuit)
    }
}
