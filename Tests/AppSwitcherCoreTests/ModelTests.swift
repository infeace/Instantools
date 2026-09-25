import CoreGraphics
import Testing
@testable import AppSwitcherCore

struct SwitcherSessionTests {
    private func entries(_ pids: [Int32]) -> [SwitcherEntry] {
        pids.map { SwitcherEntry(pid: $0, name: "\($0)", windowId: nil) }
    }

    @Test func moveWrapsBothWays() {
        var session = SwitcherSession(entries: entries([1, 2, 3]), selectedIndex: 2)
        session.move(by: 1)
        #expect(session.selectedIndex == 0)
        session.move(by: -1)
        #expect(session.selectedIndex == 2)
        session.move(by: -4)
        #expect(session.selectedIndex == 1)
    }

    @Test func reconcileKeepsSelectedApp() {
        var session = SwitcherSession(entries: entries([1, 2, 3]), selectedIndex: 1)
        session.reconcile(with: entries([4, 3, 2]))
        #expect(session.selected?.pid == 2)
        session.reconcile(with: entries([7]))
        #expect(session.selectedIndex == 0)
    }

    @Test func reconcileKeepsTheIndexWhenTheSelectedAppQuits() {
        var session = SwitcherSession(entries: entries([1, 2, 3]), selectedIndex: 1)
        session.reconcile(with: entries([1, 3]))
        #expect(session.selectedIndex == 1)
        #expect(session.selected?.pid == 3)
    }

    @Test func selectIgnoresOutOfRange() {
        var session = SwitcherSession(entries: entries([1, 2, 3]), selectedIndex: 0)
        session.select(2)
        #expect(session.selectedIndex == 2)
        session.select(3)
        #expect(session.selectedIndex == 2)
    }

    @Test func clampsInitialSelection() {
        #expect(SwitcherSession(entries: entries([1, 2]), selectedIndex: 5).selectedIndex == 1)
        #expect(SwitcherSession(entries: [], selectedIndex: 3).selected == nil)
    }
}

struct MRUListTests {
    @Test func touchMovesToFront() {
        var list = MRUList([1, 2, 3])
        list.touch(3)
        #expect(list.order == [3, 1, 2])
        list.touch(4)
        #expect(list.order == [4, 3, 1, 2])
    }

    @Test func initDeduplicates() {
        #expect(MRUList([1, 2, 1, 3, 2]).order == [1, 2, 3])
    }

    @Test func syncDropsDeadAndAppendsNew() {
        var list = MRUList([1, 2, 3])
        list.sync(with: [3, 4, 1])
        #expect(list.order == [1, 3, 4])
    }
}

struct DisplayMappingTests {
    private let displays = [
        Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        Display(id: 2, frame: CGRect(x: 1920, y: -400, width: 1080, height: 1920)),
    ]

    @Test func largestOverlapWins() {
        let mostlyRight = CGRect(x: 1800, y: 0, width: 800, height: 600)
        #expect(DisplayMapping.display(for: mostlyRight, in: displays) == 2)
        let mostlyLeft = CGRect(x: 1500, y: 0, width: 800, height: 600)
        #expect(DisplayMapping.display(for: mostlyLeft, in: displays) == 1)
    }

    @Test func offScreenIsNil() {
        #expect(DisplayMapping.display(for: CGRect(x: -5000, y: 0, width: 100, height: 100), in: displays) == nil)
    }

    @Test func placingDropsWindowsOffEveryDisplay() {
        let parked = CGRect(x: -5000, y: 0, width: 100, height: 100)
        let windows = [
            WindowRecord(id: 1, pid: 7, frame: parked),
            WindowRecord(id: 2, pid: 7, frame: CGRect(x: 2000, y: 0, width: 400, height: 400)),
            WindowRecord(id: 3, pid: 8, frame: parked),
            WindowRecord(id: 4, pid: 7, frame: CGRect(x: 100, y: 100, width: 400, height: 400)),
        ]
        let placed = DisplayMapping.placed(windows, on: displays)
        #expect(placed.windows.map(\.id) == [2, 4])
        // App 8 has only a parked window, so it has no display and no window.
        #expect(placed.displayByPid == [7: 2])
        let unknown = DisplayMapping.placed(windows, on: [])
        #expect(unknown.windows == windows)
        #expect(unknown.displayByPid.isEmpty)
    }
}

struct SessionKeyTests {
    @Test func mapsFixedKeys() {
        #expect(SessionKey(keycode: 53, characters: "\u{1b}") == .cancel)
        #expect(SessionKey(keycode: 123, characters: "\u{f702}") == .previous)
        #expect(SessionKey(keycode: 124, characters: "\u{f703}") == .next)
    }

    @Test func lettersFollowTheLayout() {
        #expect(SessionKey(keycode: 12, characters: "q") == .quit)
        #expect(SessionKey(keycode: 4, characters: "H") == .hide)
        #expect(SessionKey(keycode: 50, characters: "`") == .previous)
        // AZERTY: the US Q position types A, and Q sits where US A is.
        #expect(SessionKey(keycode: 12, characters: "a") == .app("a"))
        #expect(SessionKey(keycode: 0, characters: "q") == .quit)
    }

    @Test func nonLatinLayoutsUseTheUSPosition() {
        #expect(SessionKey(keycode: 12, characters: "я") == .quit)
        #expect(SessionKey(keycode: 4, characters: "") == .hide)
        #expect(SessionKey(keycode: 3, characters: "ф") == .app("f"))
        #expect(SessionKey(keycode: 18, characters: "") == .app("1"))
    }

    @Test func typedASCIIPunctuationMapsToNothingNotItsUSPosition() {
        // Dvorak types ' where US has Q, which must not quit the selected app.
        #expect(SessionKey(keycode: 12, characters: "'") == nil)
    }

    @Test func lettersAndDigitsAreAppKeys() {
        #expect(SessionKey(keycode: 3, characters: "F") == .app("f"))
        #expect(SessionKey(keycode: 29, characters: "0") == .app("0"))
        #expect(SessionKey(keycode: 36, characters: "\r") == nil)
        #expect(SessionKey(keycode: 49, characters: " ") == nil)
        #expect(SessionKey(keycode: 43, characters: ",") == nil)
        #expect(!SessionKey.app("f").repeats)
    }

    @Test func upAndDownExpose() {
        #expect(SessionKey(keycode: 125, characters: "\u{f701}") == .expose)
        #expect(SessionKey(keycode: 126, characters: "\u{f700}") == .expose)
        #expect(!SessionKey.expose.repeats)
    }

    @Test func onlyMovesRepeat() {
        #expect(SessionKey.next.repeats && SessionKey.previous.repeats)
        #expect(!SessionKey.quit.repeats && !SessionKey.hide.repeats)
    }
}
