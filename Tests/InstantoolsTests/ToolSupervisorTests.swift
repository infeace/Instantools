import Foundation
import InstantoolsCore
import Testing
@testable import Instantools

/// Nothing here may restore native Cmd+Tab, since that changes the setting for the whole Mac.
@MainActor
struct ToolSupervisorTests {
    @MainActor
    final class SavedMarker {
        var value = NativeSwitcherMarker(mayBeOff: false)
    }

    /// The helper passes the check before the launch but is not a program, so `Process.run()` throws after
    /// the marker was set.
    @Test func aSwitcherThatCannotBeStartedClearsTheMarker() throws {
        let files = FileManager.default
        let helpers = files.temporaryDirectory.appending(path: "ToolSupervisorTests-\(UUID().uuidString)")
        try files.createDirectory(at: helpers, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: helpers) }
        let executable = helpers.appending(path: ToolId.appSwitcher.executableName)
        #expect(files.createFile(atPath: executable.path, contents: Data(), attributes: [.posixPermissions: 0o755]))

        let saved = SavedMarker()
        let supervisor = ToolSupervisor(helpers: helpers, marker: .init(load: { saved.value }, save: { saved.value = $0 }))
        supervisor.start(.appSwitcher)

        guard case .failed(let reason) = supervisor.state(.appSwitcher) else {
            Issue.record("expected a failed start, got \(supervisor.state(.appSwitcher))")
            return
        }
        #expect(reason.hasPrefix("Could not start"))
        #expect(!saved.value.mayBeOff)
    }
}
