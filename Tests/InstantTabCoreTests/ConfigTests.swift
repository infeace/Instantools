import Foundation
import Testing
@testable import InstantTabCore

struct ConfigTests {
    private func parse(_ text: String) throws(ConfigError) -> Config.Parsed {
        try Config.parse(Data(text.utf8))
    }

    @Test func defaultFileParsesToDefaults() throws {
        let parsed = try parse(Config.defaultFileContents)
        #expect(parsed.config == Config())
        #expect(parsed.warnings.isEmpty)
    }

    @Test func fileContentsRoundTrip() throws {
        var config = Config()
        config.showDelayMs = 0
        config.scope = .mouseDisplay
        config.windowlessApps = .end
        config.iconSize = 72.5
        config.exclude = [
            .init(bundleId: "com.apple.finder", when: .noWindows),
            .init(bundleId: "com.parallels.*"),
            .init(bundleId: "odd\"id\\with/escapes"),
        ]
        config.displayGroups = [
            DisplayGroup(name: "Laptop", rules: [.builtIn]),
            DisplayGroup(name: "Desk \"left\"", rules: [.external, .portrait, .name("DELL*"), .uuid("ABC-123")]),
        ]
        config.scope = .group("Desk \"left\"")
        let parsed = try parse(config.fileContents)
        #expect(parsed.config == config)
        #expect(parsed.warnings.isEmpty)
    }

    @Test func scopeValues() throws {
        for scope: Config.Scope in [.all, .mouseDisplay, .focusedDisplay, .mouseGroup, .group("Desk")] {
            #expect(Config.Scope(rawValue: scope.rawValue) == scope)
        }
        #expect(Config.Scope(rawValue: "group:") == nil)
        #expect(Config.Scope(rawValue: "everywhere") == nil)
    }

    @Test func displayGroupErrorsAndWarnings() throws {
        #expect(throws: ConfigError.invalid("displayGroups has two groups named \"A\"")) {
            try parse("{ displayGroups: [{ name: \"A\", match: [] }, { name: \"A\", match: [] }] }")
        }
        #expect(throws: ConfigError.self) {
            try parse("{ displayGroups: [{ name: \"A\", match: [\"sideways\"] }] }")
        }
        let parsed = try parse("{ scope: \"group:Gone\" }")
        #expect(parsed.warnings == ["scope uses group 'Gone', which does not exist, so all monitors are shown"])
    }

    @Test func missingKeysKeepDefaults() throws {
        let parsed = try parse("{ scope: \"mouseDisplay\" }")
        var expected = Config()
        expected.scope = .mouseDisplay
        #expect(parsed.config == expected)
    }

    @Test func readsEveryKey() throws {
        let parsed = try parse("""
        {
          showDelayMs: 0, scope: "mouseDisplay", windowlessApps: "end", iconSize: 64,
          exclude: ["com.a", { bundleId: "com.b", when: "noWindows" }],
        }
        """)
        #expect(parsed.config.showDelayMs == 0)
        #expect(parsed.config.scope == .mouseDisplay)
        #expect(parsed.config.windowlessApps == .end)
        #expect(parsed.config.iconSize == 64)
        #expect(parsed.config.exclude == [
            .init(bundleId: "com.a"),
            .init(bundleId: "com.b", when: .noWindows),
        ])
    }

    @Test func duplicateExclusionsKeepTheFirst() throws {
        let parsed = try parse("{ exclude: [\"com.a\", { bundleId: \"COM.A\", when: \"noWindows\" }] }")
        #expect(parsed.config.exclude == [.init(bundleId: "com.a")])
        #expect(parsed.warnings == ["exclude lists 'COM.A' twice, the first rule is used"])
    }

    @Test func loneWildcardIsIgnored() throws {
        let parsed = try parse("{ exclude: [\"*\", \"com.a\"] }")
        #expect(parsed.config.exclude == [.init(bundleId: "com.a")])
        #expect(parsed.warnings == ["exclude '*' would hide every app, so it is ignored"])
    }

    @Test func unknownKeysAreWarnings() throws {
        let parsed = try parse("{ scoep: \"all\", exclude: [{ bundleId: \"com.a\", wen: \"always\" }] }")
        #expect(parsed.warnings == ["unknown key 'scoep' ignored", "unknown key 'exclude[0].wen' ignored"])
    }

    @Test func invalidValuesAreErrors() {
        #expect(throws: ConfigError.invalid("scope must be \"all\", \"mouseDisplay\", \"focusedDisplay\", \"mouseGroup\" or \"group:<name>\"")) {
            try parse("{ scope: \"everywhere\" }")
        }
        #expect(throws: ConfigError.invalid("showDelayMs must be a whole number from 0 to 500")) {
            try parse("{ showDelayMs: 12.5 }")
        }
        #expect(throws: ConfigError.invalid("showDelayMs must be a whole number from 0 to 500")) {
            try parse("{ showDelayMs: true }")
        }
        #expect(throws: ConfigError.invalid("exclude[0].bundleId must be a non-empty string")) {
            try parse("{ exclude: [{ when: \"always\" }] }")
        }
    }

    @Test func syntaxErrorsAreReported() {
        #expect {
            try parse("{ scope: ")
        } throws: { error in
            guard case .syntax = error as? ConfigError else { return false }
            return true
        }
    }

    @Test func exclusionMatching() {
        var config = Config()
        config.exclude = [
            .init(bundleId: "com.parallels.*"),
            .init(bundleId: "com.apple.finder", when: .noWindows),
        ]
        let matcher = ExclusionMatcher(config.exclude)
        #expect(matcher.isExcluded(bundleId: "com.parallels.desktop", hasWindows: true))
        #expect(!matcher.isExcluded(bundleId: "com.parallel", hasWindows: true))
        #expect(matcher.isExcluded(bundleId: "com.apple.finder", hasWindows: false))
        #expect(!matcher.isExcluded(bundleId: "com.apple.finder", hasWindows: true))
        #expect(!matcher.isExcluded(bundleId: nil, hasWindows: false))
        #expect(matcher.isExcluded(bundleId: "com.Apple.Finder", hasWindows: false))
        #expect(matcher.isExcluded(bundleId: "COM.PARALLELS.desktop", hasWindows: true))
    }
}
