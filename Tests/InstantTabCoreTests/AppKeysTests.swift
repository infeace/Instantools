import CoreGraphics
import Foundation
import Testing
@testable import InstantTabCore

struct AppKeysTests {
    private func parse(_ text: String) throws(ConfigError) -> Config.Parsed {
        try Config.parse(Data(text.utf8))
    }

    @Test func parsesAndSortsBindings() throws {
        let parsed = try parse(#"{ appKeys: { s: "com.apple.Safari", "1": "com.apple.Notes", F: "com.apple.finder" } }"#)
        #expect(parsed.config.appKeys == [
            .init(key: "1", bundleId: "com.apple.Notes"),
            .init(key: "f", bundleId: "com.apple.finder"),
            .init(key: "s", bundleId: "com.apple.Safari"),
        ])
        #expect(parsed.warnings.isEmpty)
    }

    @Test func roundTripsThroughTheFile() throws {
        var config = Config()
        config.bindAppKey("f", to: "com.apple.finder")
        config.bindAppKey("1", to: "odd\"id")
        #expect(config.fileContents.contains(#"f: "com.apple.finder","#))
        #expect(config.fileContents.contains(#""1": "odd\"id","#))
        #expect(try parse(config.fileContents).config == config)
    }

    @Test func reservedAndDuplicateKeysAreWarnings() throws {
        let parsed = try parse(#"{ appKeys: { q: "com.a", H: "com.b", F: "com.c", f: "com.d" } }"#)
        #expect(parsed.config.appKeys == [.init(key: "f", bundleId: "com.c")])
        #expect(parsed.warnings == [
            "appKeys 'H' is ignored, since H hides the selected app",
            "appKeys lists 'f' twice, the first is used",
            "appKeys 'q' is ignored, since Q quits the selected app",
        ])
    }

    @Test func invalidBindingsAreErrors() {
        #expect(throws: ConfigError.invalid("appKeys 'ab' must be a single letter or digit")) {
            try parse(#"{ appKeys: { ab: "com.a" } }"#)
        }
        #expect(throws: ConfigError.invalid("appKeys ',' must be a single letter or digit")) {
            try parse(#"{ appKeys: { ",": "com.a" } }"#)
        }
        #expect(throws: ConfigError.invalid("appKeys.f must be a bundle id")) {
            try parse(#"{ appKeys: { f: "" } }"#)
        }
        #expect(throws: ConfigError.invalid("appKeys must be an object of keys and bundle ids")) {
            try parse(#"{ appKeys: ["f"] }"#)
        }
    }

    @Test func problemsWhenBinding() {
        var config = Config()
        config.bindAppKey("f", to: "com.apple.finder")
        #expect(config.appKeyProblem("s") == nil)
        #expect(config.appKeyProblem(nil) == .notALetterOrDigit)
        #expect(config.appKeyProblem(",") == .notALetterOrDigit)
        #expect(config.appKeyProblem("q") == .reserved("q"))
        #expect(config.appKeyProblem("f") == .taken(bundleId: "com.apple.finder"))
        #expect(config.appKeyProblem("f", replacing: "f") == nil)
    }

    @Test func bindingReplacesTheOldKey() {
        var config = Config()
        config.bindAppKey("s", to: "com.apple.Safari")
        config.bindAppKey("f", to: "com.apple.finder")
        config.bindAppKey("b", to: "com.apple.Safari", replacing: "s")
        #expect(config.appKeys == [.init(key: "b", bundleId: "com.apple.Safari"), .init(key: "f", bundleId: "com.apple.finder")])
    }

    @Test func mapLooksUpBothWays() {
        let map = AppKeyMap([.init(key: "f", bundleId: "com.apple.finder"), .init(key: "g", bundleId: "com.apple.Finder")])
        #expect(map.bundleId(for: "f") == "com.apple.finder")
        #expect(map.bundleId(for: "x") == nil)
        #expect(map.key(for: "COM.APPLE.FINDER") == "f")
        #expect(map.key(for: nil) == nil)
    }

    @Test func tilesCarryTheirKey() {
        let snapshot = Snapshot(apps: [RunningApp(pid: 1, bundleId: "com.apple.finder", name: "Finder"), RunningApp(pid: 2, bundleId: "com.b", name: "B")])
        let entries = SwitcherFilter.entries(
            for: snapshot, config: Config(), exclusions: ExclusionMatcher([]),
            appKeys: AppKeyMap([.init(key: "f", bundleId: "com.apple.finder")]), displays: [], targets: nil
        )
        #expect(entries.map(\.key) == ["f", nil])
    }

    @Test func targetPrefersTheListedTileThenAnyWindowThenLaunch() {
        let map = AppKeyMap([
            .init(key: "a", bundleId: "com.a"), .init(key: "b", bundleId: "com.b"), .init(key: "c", bundleId: "com.c"),
        ])
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let snapshot = Snapshot(
            apps: [RunningApp(pid: 1, bundleId: "com.a", name: "A"), RunningApp(pid: 2, bundleId: "COM.B", name: "B")],
            windows: [WindowRecord(id: 21, pid: 2, frame: frame), WindowRecord(id: 22, pid: 2, frame: frame)]
        )
        let listed = [SwitcherEntry(pid: 1, name: "A", windowId: 11, key: "a")]
        #expect(SwitcherFilter.target(forAppKey: "a", appKeys: map, in: snapshot, listed: listed) == .running(listed[0]))
        // Not listed, as when excluded or on another display: its frontmost window.
        #expect(SwitcherFilter.target(forAppKey: "b", appKeys: map, in: snapshot, listed: listed)
            == .running(SwitcherEntry(pid: 2, name: "B", windowId: 21, key: "b")))
        #expect(SwitcherFilter.target(forAppKey: "c", appKeys: map, in: snapshot, listed: listed) == .launch(bundleId: "com.c"))
        #expect(SwitcherFilter.target(forAppKey: "z", appKeys: map, in: snapshot, listed: listed) == nil)
    }
}
