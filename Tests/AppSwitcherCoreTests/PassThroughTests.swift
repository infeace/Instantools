import Foundation
import Testing
@testable import AppSwitcherCore

struct PassThroughTests {
    private func parse(_ text: String) throws(ConfigError) -> Config.Parsed {
        try Config.parse(Data(text.utf8))
    }

    @Test func parsesAndRoundTrips() throws {
        let parsed = try parse(#"{ passThrough: ["com.parallels.desktop.console", "com.vmware.*"] }"#)
        #expect(parsed.config.passThrough == ["com.parallels.desktop.console", "com.vmware.*"])
        #expect(parsed.warnings.isEmpty)
        #expect(try parse(parsed.config.fileContents).config == parsed.config)
    }

    @Test func loneWildcardAndDuplicatesAreWarnings() throws {
        let parsed = try parse(#"{ passThrough: ["*", "com.a", "COM.A"] }"#)
        #expect(parsed.config.passThrough == ["com.a"])
        #expect(parsed.warnings == [
            "passThrough '*' would give Cmd+Tab to every app, so it is ignored",
            "passThrough lists 'COM.A' twice, the first is used",
        ])
    }

    @Test func invalidValuesAreErrors() {
        #expect(throws: ConfigError.invalid("passThrough must be a list of bundle ids")) {
            try parse(#"{ passThrough: "com.a" }"#)
        }
        #expect(throws: ConfigError.invalid("passThrough[1] must be a bundle id")) {
            try parse(#"{ passThrough: ["com.a", 3] }"#)
        }
    }

    @Test func matcherHandlesPrefixesAndCase() {
        let matcher = BundleIdMatcher(["com.vmware.*", "com.apple.ScreenSharing"])
        #expect(matcher.matches("com.vmware.fusion"))
        #expect(matcher.matches("com.apple.screensharing"))
        #expect(!matcher.matches("com.apple.finder"))
        #expect(!matcher.matches(nil))
        #expect(!BundleIdMatcher([]).matches("com.a"))
    }
}
