import Testing
@testable import InstantTabCore

struct AltTabImportTests {
    @Test func importsHideRulesOnly() {
        let json = #"""
        [{"hide":"1","ignore":"0","bundleIdentifier":"com.McAfee.McAfeeSafariHost"},
         {"hide":"2","ignore":"0","bundleIdentifier":"com.apple.finder"},
         {"hide":"0","ignore":"2","bundleIdentifier":"com.microsoft.rdc.macos"},
         {"hide":"1","ignore":"0","bundleIdentifier":""}]
        """#
        #expect(AltTabImport.exclusions(fromExceptionsJSON: json) == [
            .init(bundleId: "com.McAfee.McAfeeSafariHost", when: .always),
            .init(bundleId: "com.apple.finder", when: .noWindows),
        ])
    }

    @Test func malformedJSONImportsNothing() {
        #expect(AltTabImport.exclusions(fromExceptionsJSON: "not json").isEmpty)
    }

    @Test func addingSkipsAppsAlreadyExcluded() {
        var config = Config()
        config.exclude = [.init(bundleId: "com.apple.Finder", when: .always)]
        config.addExclusions([.init(bundleId: "com.apple.finder", when: .noWindows), .init(bundleId: "com.b")])
        #expect(config.exclude == [.init(bundleId: "com.apple.Finder", when: .always), .init(bundleId: "com.b")])
    }
}
