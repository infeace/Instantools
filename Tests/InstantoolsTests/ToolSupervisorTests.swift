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

    /// A shell script in InstantLang's place, which has no native Cmd+Tab to restore. It adds a line to
    /// `starts` each time the supervisor starts it, then runs `body`.
    private func stub(_ body: String) throws -> (helpers: URL, starts: URL) {
        let files = FileManager.default
        let helpers = files.temporaryDirectory.appending(path: "ToolSupervisorTests-\(UUID().uuidString)")
        try files.createDirectory(at: helpers, withIntermediateDirectories: true)
        let starts = helpers.appending(path: "starts")
        let script = "#!/bin/sh\n[ \"$1\" = warm ] && exit 0\necho $$ >> '\(starts.path)'\n\(body)\n"
        let executable = helpers.appending(path: ToolId.layoutSwitcher.executableName)
        #expect(files.createFile(atPath: executable.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755]))
        // macOS checks a new file on its first exec, which here took from 0.2 to over 0.6 seconds, longer than
        // these tests give a tool to become ready.
        let warm = Process()
        warm.executableURL = executable
        warm.arguments = ["warm"]
        try warm.run()
        warm.waitUntilExit()
        return (helpers, starts)
    }

    private func startCount(_ starts: URL) -> Int {
        ((try? String(contentsOf: starts, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    /// Exits arrive on the main queue, which runs while this waits.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func supervise(_ helpers: URL) -> ToolSupervisor {
        let saved = SavedMarker()
        return ToolSupervisor(helpers: helpers, marker: .init(load: { saved.value }, save: { saved.value = $0 }), checkInterval: 0.1)
    }

    private static let ready = #"echo '{"event":"ready"}'"#

    @Test func aToolThatNeverBecomesReadyIsKilledAndRestarted() async throws {
        let (helpers, starts) = try stub("exec sleep 60")
        defer { try? FileManager.default.removeItem(at: helpers) }
        let supervisor = supervise(helpers)
        defer { supervisor.stopAllAndWait() }
        supervisor.start(.layoutSwitcher)

        #expect(try await eventually { startCount(starts) >= 2 })
    }

    @Test func aToolThatStopsAnsweringIsKilledAndRestarted() async throws {
        let (helpers, starts) = try stub("\(Self.ready)\nexec sleep 60")
        defer { try? FileManager.default.removeItem(at: helpers) }
        let supervisor = supervise(helpers)
        defer { supervisor.stopAllAndWait() }
        supervisor.start(.layoutSwitcher)

        #expect(try await eventually { supervisor.state(.layoutSwitcher) == .running })
        #expect(try await eventually { startCount(starts) >= 2 })
    }

    @Test func aToolThatAnswersKeepsRunning() async throws {
        let (helpers, starts) = try stub(#"\#(Self.ready)\#nwhile read line; do echo '{"event":"pong"}'; done"#)
        defer { try? FileManager.default.removeItem(at: helpers) }
        let supervisor = supervise(helpers)
        defer { supervisor.stopAllAndWait() }
        supervisor.start(.layoutSwitcher)

        #expect(try await eventually { supervisor.state(.layoutSwitcher) == .running })
        // Many times the reply limit.
        try await Task.sleep(for: .milliseconds(1500))
        #expect(supervisor.state(.layoutSwitcher) == .running)
        #expect(startCount(starts) == 1)
    }
}
