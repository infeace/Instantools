import CoreGraphics
import Testing
@testable import InstantTabCore

struct DisplayGroupsTests {
    // A laptop below-left of a landscape external, and a portrait external on the right.
    private let laptop = Display(id: 1, frame: CGRect(x: 0, y: 1080, width: 1512, height: 982), uuid: "L", name: "Built-in Retina Display", isBuiltIn: true)
    private let wide = Display(id: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), uuid: "W", name: "DELL S2722QC", isMain: true)
    private let tall = Display(id: 3, frame: CGRect(x: 1920, y: -200, width: 1080, height: 1920), uuid: "T", name: "L27m-30")
    private var all: [Display] { [laptop, wide, tall] }

    private func members(_ rules: [DisplayRule]) -> Set<UInt32> {
        DisplayGroup(name: "G", rules: rules).members(in: all)
    }

    @Test func kindShapeAndMainRules() {
        #expect(members([.builtIn]) == [1])
        #expect(members([.external]) == [2, 3])
        #expect(members([.portrait]) == [3])
        #expect(members([.landscape]) == [1, 2])
        #expect(members([.main]) == [2])
    }

    @Test func positionRules() {
        #expect(members([.leftmost]) == [1, 2])
        #expect(members([.rightmost]) == [3])
        #expect(members([.topmost]) == [3])
        #expect(members([.bottommost]) == [1])
    }

    @Test func nameAndUuidRules() {
        #expect(members([.name("dell*")]) == [2])
        #expect(members([.name("*27*")]) == [2, 3])
        #expect(members([.uuid("t")]) == [3])
        #expect(members([.builtIn, .portrait]) == [1, 3])
        #expect(members([]).isEmpty)
    }

    @Test func scopeTargets() {
        let groups = ResolvedGroups([
            DisplayGroup(name: "Desk", rules: [.external]),
            DisplayGroup(name: "Gone", rules: [.uuid("missing")]),
        ], displays: all)
        func targets(_ scope: Config.Scope, mouse: UInt32? = 1, focused: UInt32? = nil) -> Set<UInt32>? {
            DisplayScope.targets(for: scope, groups: groups, mouseDisplay: mouse, focusedDisplay: focused)
        }
        #expect(targets(.all) == nil)
        #expect(targets(.mouseDisplay) == [1])
        #expect(targets(.focusedDisplay, focused: 3) == [3])
        #expect(targets(.focusedDisplay, focused: nil) == [1])
        #expect(targets(.mouseGroup, mouse: 2) == [2, 3])
        #expect(targets(.mouseGroup, mouse: 1) == [1])
        #expect(targets(.group("Desk")) == [2, 3])
        #expect(targets(.group("Gone")) == nil)
        #expect(targets(.group("Unknown")) == nil)
        #expect(targets(.mouseDisplay, mouse: nil) == nil)
    }

    @Test func focusedDisplayFollowsFrontmostWindow() {
        let snapshot = Snapshot(windows: [
            WindowRecord(id: 1, pid: 9, frame: CGRect(x: 2000, y: 100, width: 500, height: 500)),
            WindowRecord(id: 2, pid: 7, frame: CGRect(x: 100, y: 100, width: 500, height: 500)),
        ])
        #expect(DisplayScope.focusedDisplay(in: snapshot, frontmostPid: 7, displays: all) == 2)
        #expect(DisplayScope.focusedDisplay(in: snapshot, frontmostPid: 9, displays: all) == 3)
        #expect(DisplayScope.focusedDisplay(in: snapshot, frontmostPid: 5, displays: all) == nil)
    }
}
