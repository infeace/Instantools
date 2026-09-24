import CoreGraphics
import Testing
@testable import InstantTabCore

struct SwitcherFilterTests {
    // Two side-by-side displays, 1 on the left and 2 on the right.
    private let displays = [
        Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        Display(id: 2, frame: CGRect(x: 1920, y: 0, width: 1080, height: 1920)),
    ]
    private let left = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let right = CGRect(x: 2000, y: 100, width: 800, height: 600)

    private func app(_ pid: Int32, _ bundleId: String? = nil) -> RunningApp {
        RunningApp(pid: pid, bundleId: bundleId ?? "app.\(pid)", name: "App \(pid)")
    }

    private func pids(_ entries: [SwitcherEntry]) -> [Int32] { entries.map(\.pid) }

    @Test func allScopeKeepsRecentOrderAndFrontWindow() {
        let snapshot = Snapshot(
            apps: [app(1), app(2), app(3)],
            windows: [
                WindowRecord(id: 20, pid: 2, frame: right),
                WindowRecord(id: 10, pid: 1, frame: left),
                WindowRecord(id: 11, pid: 1, frame: right),
            ]
        )
        let entries = SwitcherFilter.entries(for: snapshot, config: Config(), displays: displays, mouseDisplay: 1)
        #expect(pids(entries) == [1, 2, 3])
        #expect(entries.map(\.windowId) == [10, 20, nil])
    }

    @Test func windowlessPlacement() {
        let snapshot = Snapshot(apps: [app(1), app(2), app(3)], windows: [WindowRecord(id: 30, pid: 3, frame: left)])
        var config = Config()
        config.windowlessApps = .end
        #expect(pids(SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: nil)) == [3, 1, 2])
        config.windowlessApps = .hide
        #expect(pids(SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: nil)) == [3])
    }

    @Test func exclusions() {
        let snapshot = Snapshot(
            apps: [app(1, "com.apple.finder"), app(2, "com.excluded"), app(3)],
            windows: [WindowRecord(id: 30, pid: 3, frame: left)]
        )
        var config = Config()
        config.exclude = [.init(bundleId: "com.apple.finder", when: .noWindows), .init(bundleId: "com.excluded")]
        #expect(pids(SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: nil)) == [3])
    }

    @Test func mouseDisplayScopeUsesWindowsOnThatDisplay() {
        let snapshot = Snapshot(
            apps: [app(1), app(2), app(3)],
            windows: [
                WindowRecord(id: 11, pid: 1, frame: right),
                WindowRecord(id: 10, pid: 1, frame: left),
                WindowRecord(id: 20, pid: 2, frame: right),
            ]
        )
        var config = Config()
        config.scope = .mouseDisplay
        let onLeft = SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: 1)
        #expect(pids(onLeft) == [1, 3])
        #expect(onLeft.first?.windowId == 10)
        let onRight = SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: 2)
        #expect(pids(onRight) == [1, 2, 3])
        #expect(onRight.first?.windowId == 11)
    }

    @Test func hiddenAppsStayWithTheirLastDisplay() {
        let snapshot = Snapshot(apps: [app(1), app(2), app(3)], windows: [], lastDisplayByPid: [1: 1, 2: 2, 3: 99])
        var config = Config()
        config.scope = .mouseDisplay
        // Display 99 is disconnected, so app 3 is treated as never seen and shown everywhere.
        #expect(pids(SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: 1)) == [1, 3])
        #expect(pids(SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: 2)) == [2, 3])
    }

    @Test func unknownMouseDisplayFallsBackToAll() {
        let snapshot = Snapshot(apps: [app(1), app(2)], windows: [WindowRecord(id: 20, pid: 2, frame: right)])
        var config = Config()
        config.scope = .mouseDisplay
        #expect(pids(SwitcherFilter.entries(for: snapshot, config: config, displays: displays, mouseDisplay: nil)) == [1, 2])
    }

    @Test func initialIndexMatchesNative() {
        #expect(SwitcherFilter.initialIndex(count: 3, firstIsFrontmost: true, reverse: false) == 1)
        #expect(SwitcherFilter.initialIndex(count: 3, firstIsFrontmost: false, reverse: false) == 0)
        #expect(SwitcherFilter.initialIndex(count: 1, firstIsFrontmost: true, reverse: false) == 0)
        #expect(SwitcherFilter.initialIndex(count: 3, firstIsFrontmost: true, reverse: true) == 2)
        #expect(SwitcherFilter.initialIndex(count: 0, firstIsFrontmost: false, reverse: false) == 0)
    }
}
