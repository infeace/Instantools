import Testing
@testable import AppSwitcherCore

struct WildcardTests {
    @Test func wildcardsAndCase() {
        #expect(Wildcard.matches("dell*", "DELL S2722QC"))
        #expect(Wildcard.matches("*27*", "L27m-30"))
        #expect(Wildcard.matches("l?7M-30", "L27m-30"))
        #expect(Wildcard.matches("a*b*c", "aXXbYYc"))
        #expect(!Wildcard.matches("a*b*c", "aXXbYY"))
        #expect(!Wildcard.matches("dell", "DELL S2722QC"))
        #expect(Wildcard.matches("*", ""))
        #expect(Wildcard.matches("", ""))
        #expect(!Wildcard.matches("?", ""))
        #expect(!Wildcard.matches("", "a"))
    }

    @Test func backslashIsAnEscapeAndLiteralAtTheEnd() {
        #expect(Wildcard.matches("\\*", "*"))
        #expect(!Wildcard.matches("\\*", "x"))
        #expect(Wildcard.matches("DELL\\", "dell\\"))
        #expect(!Wildcard.matches("DELL\\", "DELL"))
        #expect(!Wildcard.matches("DELL\\", "DELL S2722QC"))
    }

    @Test func manyStarsStayFast() {
        #expect(!Wildcard.matches("*a*a*a*a*a*a*b", String(repeating: "a", count: 2_000)))
    }
}
