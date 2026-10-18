import Foundation
import InstantoolsCore
import Testing
@testable import WindowSnapperCore

struct SnapConfigTests {
    private func parse(_ text: String) throws(ConfigError) -> ParsedConfig<SnapConfig> {
        try SnapConfig.parse(Data(text.utf8))
    }

    @Test func defaultFileParsesToDefaults() throws {
        let parsed = try parse(SnapConfig.defaultFileContents)
        #expect(parsed.config == SnapConfig())
        #expect(parsed.warnings.isEmpty)
    }

    @Test func defaultsAreRectanglesShortcuts() {
        let config = SnapConfig()
        #expect(config.shortcut(for: .leftHalf)?.text == "ctrl+opt+left")
        #expect(config.shortcut(for: .maximize)?.text == "ctrl+opt+return")
        #expect(config.shortcut(for: .nextDisplay)?.text == "ctrl+opt+cmd+right")
        #expect(config.boundShortcuts.count == SnapAction.allCases.count)
        #expect(Set(config.boundShortcuts.map(\.shortcut)).count == SnapAction.allCases.count)
    }

    @Test func fileContentsRoundTrip() throws {
        var config = SnapConfig()
        config.dragToSnap = false
        config.gap = 12
        config.repeatMode = .nextDisplay
        config.setShortcut(Shortcut("ctrl+opt+s"), for: .maximize)
        config.setShortcut(nil, for: .center)
        config.setShortcut(Shortcut("f13"), for: .restore)
        let parsed = try parse(config.fileContents)
        #expect(parsed.config == config)
        #expect(parsed.warnings.isEmpty)
        #expect(try config.checkedFileContents() == config.fileContents)
    }

    @Test func missingKeysKeepDefaults() throws {
        let parsed = try parse("{ gap: 4, shortcuts: { maximize: \"ctrl+opt+s\" } }")
        var expected = SnapConfig()
        expected.gap = 4
        expected.setShortcut(Shortcut("ctrl+opt+s"), for: .maximize)
        #expect(parsed.config == expected)
    }

    @Test func invalidValues() {
        #expect(throws: ConfigError.invalid("gap must be a whole number from 0 to 40")) { try parse("{ gap: 41 }") }
        #expect(throws: ConfigError.invalid("gap must be a whole number from 0 to 40")) { try parse("{ gap: true }") }
        #expect(throws: ConfigError.invalid("dragToSnap must be true or false")) { try parse("{ dragToSnap: 1 }") }
        #expect(throws: ConfigError.invalid(#"repeat must be one of "nextDisplay", "cycleSizes", "none""#)) { try parse("{ repeat: \"again\" }") }
        #expect(throws: ConfigError.invalid(#"shortcuts.leftHalf 'left' must be keys such as "ctrl+opt+left", with ctrl, opt or cmd unless the key is f1 to f20"#)) {
            try parse("{ shortcuts: { leftHalf: \"left\" } }")
        }
        #expect(throws: ConfigError.invalid(#"shortcuts.leftHalf must be keys such as "ctrl+opt+left", or "" for none"#)) {
            try parse("{ shortcuts: { leftHalf: 1 } }")
        }
    }

    @Test func clashesKeepOneShortcut() throws {
        // Set in the file, so it wins over center's default.
        let parsed = try parse("{ shortcuts: { maximize: \"ctrl+opt+c\" } }")
        #expect(parsed.config.shortcut(for: .maximize)?.text == "ctrl+opt+c")
        #expect(parsed.config.shortcut(for: .center) == nil)
        #expect(parsed.warnings.isEmpty)

        let both = try parse("{ shortcuts: { leftHalf: \"ctrl+opt+x\", rightHalf: \"ctrl+opt+x\" } }")
        #expect(both.config.shortcut(for: .leftHalf)?.text == "ctrl+opt+x")
        #expect(both.config.shortcut(for: .rightHalf) == nil)
        #expect(both.warnings == ["shortcuts.rightHalf uses ctrl+opt+x like shortcuts.leftHalf, which keeps it"])
    }

    @Test func unknownKeysAreWarnings() throws {
        let parsed = try parse("{ gapp: 3, shortcuts: { leftHalff: \"ctrl+opt+x\" } }")
        #expect(parsed.warnings == ["unknown key 'gapp' ignored", "unknown action 'shortcuts.leftHalff' ignored"])
    }
}

struct ShortcutTests {
    @Test func parsesAndWritesBack() throws {
        let shortcut = try #require(Shortcut("Control+Option+Left"))
        #expect(shortcut.text == "ctrl+opt+left")
        #expect(shortcut.symbols == "⌃⌥←")
        #expect(Shortcut("cmd+shift+opt+ctrl+k")?.text == "ctrl+opt+shift+cmd+k")
        #expect(Shortcut("ctrl+opt+backspace")?.text == "ctrl+opt+delete")
        #expect(Shortcut("ctrl+opt+=")?.symbols == "⌃⌥=")
        #expect(Shortcut("ctrl+opt+forwardDelete")?.keyCode == 117)
        #expect(Shortcut("ctrl + opt + c")?.text == "ctrl+opt+c")
        #expect(Shortcut("⌃⌥←")?.text == "ctrl+opt+left")
        #expect(Shortcut("⌃⌥⇧⌘K")?.text == "ctrl+opt+shift+cmd+k")
        #expect(Shortcut("⌃+⌥+return")?.text == "ctrl+opt+return")
        #expect(Shortcut("⌃⌥") == nil)
    }

    @Test func refusesWhatWouldTakeAKeyFromTyping() {
        #expect(Shortcut("left") == nil)
        #expect(Shortcut("shift+a") == nil)
        #expect(Shortcut("f13")?.text == "f13")
        #expect(Shortcut("forwardDelete") == nil)
        #expect(Shortcut("shift+forwardDelete") == nil)
        #expect(Shortcut(keyCode: 117, modifiers: []) == nil)
        #expect(Shortcut("ctrl+ctrl+a") == nil)
        #expect(Shortcut("ctrl+hyper+a") == nil)
        #expect(Shortcut("ctrl+opt+") == nil)
        #expect(Shortcut("") == nil)
    }
}

struct RectangleImportTests {
    @Test func takesChangedShortcutsRepeatAndGap() {
        let defaults: [String: Any] = [
            "maximize": ["keyCode": 1, "modifierFlags": 786432],
            "almostMaximize": [String: Any](),
            "center": [String: Any](),
            "subsequentExecutionMode": 1,
            "gapSize": 7.6,
            "alternateDefaultShortcuts": 1,
        ]
        #expect(RectangleImport.hasSettings(defaults))
        let config = RectangleImport.config(from: defaults)
        #expect(config.shortcut(for: .maximize)?.text == "ctrl+opt+s")
        #expect(config.shortcut(for: .center) == nil)
        #expect(config.shortcut(for: .leftHalf)?.text == "ctrl+opt+left")
        #expect(config.repeatMode == .nextDisplay)
        #expect(config.gap == 8)
        #expect(config.dragToSnap)
    }

    @Test func aMovedShortcutLeavesNoClash() {
        // Center moved onto left half's default.
        let config = RectangleImport.config(from: ["alternateDefaultShortcuts": 1, "center": ["keyCode": 123, "modifierFlags": 786432]])
        #expect(config.shortcut(for: .center)?.text == "ctrl+opt+left")
        #expect(config.shortcut(for: .leftHalf) == nil)
    }

    @Test func snappingOffAndUnknownKeys() {
        let defaults: [String: Any] = ["alternateDefaultShortcuts": 1, "windowSnapping": 2, "maximize": ["keyCode": 76, "modifierFlags": 786432]]
        let config = RectangleImport.config(from: defaults)
        #expect(!config.dragToSnap)
        // Keypad Enter has no name here, and the default is the key the user moved maximize away from.
        #expect(config.shortcut(for: .maximize) == nil)
        #expect(RectangleImport.hasSettings(["windowSnapping": 2]))
        #expect(!RectangleImport.hasSettings(["SUEnableAutomaticChecks": 1]))
    }

    @Test func theSpectacleSetFillsWhatWasNotChanged() {
        for defaults: [String: Any] in [["alternateDefaultShortcuts": 0], ["gapSize": 4]] {
            var withCenter = defaults
            withCenter["center"] = ["keyCode": 8, "modifierFlags": 786432]
            let config = RectangleImport.config(from: withCenter)
            #expect(config.shortcut(for: .leftHalf)?.text == "opt+cmd+left")
            #expect(config.shortcut(for: .maximize)?.text == "opt+cmd+f")
            #expect(config.shortcut(for: .topLeft)?.text == "ctrl+cmd+left")
            #expect(config.shortcut(for: .firstThird) == nil)
            #expect(config.shortcut(for: .center)?.text == "ctrl+opt+c")
        }
    }

    @Test func repeatModes() {
        let modes: [Int: RepeatMode] = [0: .cycleSizes, 1: .nextDisplay, 2: .none, 3: .nextDisplay, 4: .nextDisplay]
        for (value, mode) in modes {
            #expect(RectangleImport.config(from: ["subsequentExecutionMode": value]).repeatMode == mode)
        }
    }

    @Test func gapsOutOfRangeAreClamped() {
        #expect(RectangleImport.config(from: ["gapSize": 1e20]).gap == SnapConfig.maxGap)
        #expect(RectangleImport.config(from: ["gapSize": -5]).gap == 0)
        #expect(RectangleImport.config(from: ["gapSize": Double.nan]).gap == 0)
        #expect(RectangleImport.config(from: ["gapSize": Double.infinity]).gap == 0)
    }
}
