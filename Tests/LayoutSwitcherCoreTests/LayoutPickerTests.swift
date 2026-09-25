import Testing
@testable import LayoutSwitcherCore

struct LayoutPickerTests {
    private let two = ["abc", "bg"]
    private let three = ["abc", "bg", "de"]

    @Test func twoLayoutsFlip() {
        #expect(LayoutPicker.target(among: two, current: "abc", previous: nil) == "bg")
        #expect(LayoutPicker.target(among: two, current: "bg", previous: nil) == "abc")
        #expect(LayoutPicker.target(among: two, current: "bg", previous: "abc") == "abc")
    }

    @Test func previousWinsOverListOrder() {
        #expect(LayoutPicker.target(among: three, current: "abc", previous: "de") == "de")
    }

    @Test func removedPreviousFallsBackToNext() {
        #expect(LayoutPicker.target(among: two, current: "bg", previous: "de") == "abc")
        #expect(LayoutPicker.target(among: three, current: "de", previous: "gone") == "abc")
    }

    @Test func unknownCurrentPicksPreviousThenFirst() {
        #expect(LayoutPicker.target(among: two, current: "kotoeri", previous: "bg") == "bg")
        #expect(LayoutPicker.target(among: two, current: "kotoeri", previous: nil) == "abc")
        #expect(LayoutPicker.target(among: two, current: nil, previous: nil) == "abc")
    }

    @Test func nothingToSwitchTo() {
        #expect(LayoutPicker.target(among: ["abc"], current: "abc", previous: nil) == nil)
        #expect(LayoutPicker.target(among: [], current: "abc", previous: "bg") == nil)
    }

    @Test func historyKeepsTheOneBefore() {
        var history = LayoutHistory(current: "abc")
        history.observe("bg")
        #expect(history.previous == "abc")
        history.observe("bg") // The notification for a switch already recorded.
        #expect(history.previous == "abc")
        history.observe("abc")
        #expect(history.current == "abc")
        #expect(history.previous == "bg")
    }
}
