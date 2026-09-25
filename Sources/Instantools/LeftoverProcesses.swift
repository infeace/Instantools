import AppKit
import Darwin
import InstantoolsCore
import InstantoolsKit

/// Runs at launch, before any tool starts, and waits for everything it stops.
@MainActor
enum LeftoverProcesses {
    /// The old apps go too, and must be gone first: InstantTab turns native Cmd+Tab back on as it quits, and
    /// quitting after the new switcher turned it off would leave two switchers on one key.
    static func stop() {
        var pids = Migration.OldApp.allCases.flatMap { app in
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).map(\.processIdentifier)
        }
        pids += toolPids()
        pids = pids.filter { $0 > 0 && $0 != getpid() }
        guard !pids.isEmpty else { return }
        Diagnostics.log.notice("stopping leftover processes \(pids.map(String.init).joined(separator: ", "), privacy: .public)")
        terminate(pids)
    }

    /// Tools left running by a host that crashed or was killed, or by another install, found by file name.
    static func toolPids() -> [pid_t] {
        let names = Set(ToolId.allCases.map(\.executableName))
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(Int(count)).filter { pid in
            guard pid > 0 else { return false }
            let length = proc_pidpath(pid, &path, UInt32(path.count))
            guard length > 0 else { return false }
            let executable = String(decoding: path.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return names.contains(URL(fileURLWithPath: executable).lastPathComponent)
        }
    }

    /// SIGTERM, then SIGKILL for any still there after the stop timeout.
    static func terminate(_ pids: [pid_t]) {
        func alive() -> [pid_t] { pids.filter { kill($0, 0) == 0 } }
        for pid in pids { kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(ToolLaunch.stopTimeout)
        while !alive().isEmpty, Date() < deadline { usleep(50_000) }
        let stuck = alive()
        guard !stuck.isEmpty else { return }
        for pid in stuck { kill(pid, SIGKILL) }
        for _ in 0..<20 where !alive().isEmpty { usleep(50_000) }
    }
}
