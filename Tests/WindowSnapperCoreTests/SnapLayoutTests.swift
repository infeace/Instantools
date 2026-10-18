import CoreGraphics
import Testing
@testable import WindowSnapperCore

struct SnapLayoutTests {
    /// A 1920x1080 main display with a 25pt menu bar, and a portrait 1080x1920 one to its right.
    private let main = SnapScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visible: CGRect(x: 0, y: 25, width: 1920, height: 1055))
    private let side = SnapScreen(frame: CGRect(x: 1920, y: -400, width: 1080, height: 1920), visible: CGRect(x: 1920, y: -400, width: 1080, height: 1920))
    private let window = CGRect(x: 300, y: 200, width: 800, height: 600)

    private func plan(_ action: SnapAction, _ window: CGRect? = nil, last: SnapRecord? = nil, repeat mode: RepeatMode = .cycleSizes, gap: CGFloat = 0) -> SnapPlan? {
        SnapLayout.plan(action, window: window ?? self.window, screens: [main, side], last: last, repeatMode: mode, gap: gap)
    }

    @Test func halvesAndQuartersFillTheVisibleArea() {
        #expect(plan(.leftHalf)?.frame == CGRect(x: 0, y: 25, width: 960, height: 1055))
        #expect(plan(.rightHalf)?.frame == CGRect(x: 960, y: 25, width: 960, height: 1055))
        #expect(plan(.topHalf)?.frame == CGRect(x: 0, y: 25, width: 1920, height: 528))
        #expect(plan(.bottomHalf)?.frame == CGRect(x: 0, y: 553, width: 1920, height: 527))
        #expect(plan(.bottomRight)?.frame == CGRect(x: 960, y: 553, width: 960, height: 527))
        #expect(plan(.maximize)?.frame == main.visible)
    }

    @Test func thirdsTurnWithTheMonitor() {
        #expect(plan(.firstThird)?.frame == CGRect(x: 0, y: 25, width: 640, height: 1055))
        #expect(plan(.lastTwoThirds)?.frame == CGRect(x: 640, y: 25, width: 1280, height: 1055))
        let onSide = CGRect(x: 2000, y: 0, width: 500, height: 500)
        #expect(plan(.firstThird, onSide)?.frame == CGRect(x: 1920, y: -400, width: 1080, height: 640))
        #expect(plan(.centerThird, onSide)?.frame == CGRect(x: 1920, y: 240, width: 1080, height: 640))
    }

    @Test func gapsAreWholeAtScreenEdgesAndHalvedBetweenWindows() {
        #expect(plan(.leftHalf, gap: 10)?.frame == CGRect(x: 10, y: 35, width: 945, height: 1035))
        #expect(plan(.rightHalf, gap: 10)?.frame == CGRect(x: 965, y: 35, width: 945, height: 1035))
        #expect(plan(.maximize, gap: 10)?.frame == CGRect(x: 10, y: 35, width: 1900, height: 1035))
    }

    @Test func centerKeepsTheSizeAndFitsTheScreen() {
        #expect(plan(.center)?.frame == CGRect(x: 560, y: 253, width: 800, height: 600))
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        #expect(plan(.center, huge)?.frame == main.visible)
    }

    @Test func aRepeatedHalfCyclesSizes() throws {
        let half = try #require(plan(.leftHalf))
        let twoThirds = try #require(plan(.leftHalf, half.frame, last: SnapRecord(action: .leftHalf, step: half.step, frame: half.frame)))
        #expect(twoThirds.frame.width == 1280)
        let third = try #require(plan(.leftHalf, twoThirds.frame, last: SnapRecord(action: .leftHalf, step: twoThirds.step, frame: twoThirds.frame)))
        #expect(third.frame.width == 640)
        let back = try #require(plan(.leftHalf, third.frame, last: SnapRecord(action: .leftHalf, step: third.step, frame: third.frame)))
        #expect(back.frame.width == 960)
    }

    @Test func aWindowMovedSinceTheLastSnapStartsOver() {
        let half = CGRect(x: 0, y: 25, width: 960, height: 1055)
        let moved = half.offsetBy(dx: 50, dy: 0)
        #expect(plan(.leftHalf, moved, last: SnapRecord(action: .leftHalf, frame: half))?.frame == half)
    }

    @Test func aRepeatedHalfTravelsAcrossMonitors() throws {
        let right = CGRect(x: 960, y: 25, width: 960, height: 1055)
        let onward = try #require(plan(.rightHalf, right, last: SnapRecord(action: .rightHalf, frame: right), repeat: .nextDisplay))
        #expect(onward.action == .leftHalf)
        #expect(onward.frame == CGRect(x: 1920, y: -400, width: 540, height: 1920))
        // Nothing further left of the main display.
        let left = CGRect(x: 0, y: 25, width: 960, height: 1055)
        #expect(plan(.leftHalf, left, last: SnapRecord(action: .leftHalf, frame: left), repeat: .nextDisplay) == nil)
        // Top and bottom halves stay put.
        let top = CGRect(x: 0, y: 25, width: 1920, height: 528)
        #expect(plan(.topHalf, top, last: SnapRecord(action: .topHalf, frame: top), repeat: .nextDisplay)?.frame == top)
    }

    @Test func aSnappedWindowTakesTheSamePlaceOnTheNextMonitor() throws {
        let leftHalf = try #require(plan(.leftHalf, gap: 10))
        let moved = try #require(plan(.nextDisplay, leftHalf.frame, last: SnapRecord(action: .leftHalf, frame: leftHalf.frame), gap: 10))
        #expect(moved.action == .leftHalf)
        #expect(moved.frame == CGRect(x: 1930, y: -390, width: 525, height: 1900))
        let twoThirds = CGRect(x: 0, y: 25, width: 1280, height: 1055)
        let cycled = try #require(plan(.nextDisplay, twoThirds, last: SnapRecord(action: .leftHalf, step: 1, frame: twoThirds)))
        #expect(cycled.frame == CGRect(x: 1920, y: -400, width: 720, height: 1920))
        #expect(cycled.step == 1)
    }

    @Test func anyOtherWindowKeepsItsSize() throws {
        let moved = try #require(plan(.nextDisplay))
        #expect(moved.frame.size == window.size)
        #expect(side.visible.contains(moved.frame))
        // A side spanning the whole visible area spans the whole of the next one.
        #expect(plan(.nextDisplay, CGRect(x: 0, y: 25, width: 960, height: 1055))?.frame == CGRect(x: 1920, y: -400, width: 960, height: 1920))
        #expect(plan(.nextDisplay, main.visible)?.frame == side.visible)
        // Too wide for the portrait monitor.
        #expect(plan(.nextDisplay, CGRect(x: 100, y: 100, width: 1500, height: 500))?.frame.width == 1080)
        #expect(SnapLayout.plan(.nextDisplay, window: window, screens: [main], last: nil, repeatMode: .none, gap: 0) == nil)
    }

    @Test func displaysGoInOrderFromLeftToRight() {
        let left = SnapScreen(frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), visible: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let screens = [main, side, left]
        func target(_ action: SnapAction) -> Int? {
            SnapLayout.plan(action, window: window, screens: screens, last: nil, repeatMode: .none, gap: 0)
                .flatMap { SnapLayout.screenIndex(for: $0.frame, in: screens) }
        }
        #expect(target(.nextDisplay) == 1)
        #expect(target(.previousDisplay) == 2)
    }

    @Test func aWindowBelongsToTheScreenWithMostOfIt() {
        #expect(SnapLayout.screenIndex(for: CGRect(x: 1800, y: 0, width: 400, height: 100), in: [main, side]) == 1)
        // Off every screen, the nearest.
        #expect(SnapLayout.screenIndex(for: CGRect(x: 5000, y: 0, width: 100, height: 100), in: [main, side]) == 1)
        #expect(SnapLayout.screenIndex(for: .zero, in: []) == nil)
    }

    @Test func restoreIsLeftToTheCaller() {
        #expect(plan(.restore) == nil)
    }
}
