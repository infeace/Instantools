import AppKit
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit

/// Runs each enabled tool as a child process. Tools are started only here, with Process: macOS then treats
/// them as part of Instantools, so they share its permissions. Opened through LaunchServices or launchd they
/// would be apps of their own, each with its own permission prompts.
@MainActor
final class ToolSupervisor {
    private var runners: [ToolId: ToolRunner] = [:]
    var onChange: (() -> Void)?

    init() {
        for tool in ToolId.allCases {
            let runner = ToolRunner(tool: tool)
            runner.onChange = { [weak self] in self?.onChange?() }
            runners[tool] = runner
        }
        // The tool restores native Cmd+Tab on its own way out. A kill or a crash it could not handle skips
        // that, so the host does it before anything else.
        runners[.appSwitcher]?.afterUncleanExit = { NativeSwitcher.restore() }
    }

    func state(_ tool: ToolId) -> ToolState {
        runners[tool]?.state ?? .off
    }

    func start(_ tool: ToolId) {
        runners[tool]?.start()
    }

    func stop(_ tool: ToolId) {
        runners[tool]?.stop()
    }

    /// After it gave up, or when it could not be started.
    func retry(_ tool: ToolId) {
        runners[tool]?.retry()
    }

    var appSwitcherStatus: AppSwitcherStatus? {
        runners[.appSwitcher]?.latest?.appSwitcher
    }

    var layoutSwitcherStatus: LayoutSwitcherStatus? {
        runners[.layoutSwitcher]?.latest?.layoutSwitcher
    }

    /// Replies arrive through `onChange`.
    func requestStatus() {
        for runner in runners.values { runner.request(.status) }
    }

    /// Blocks for up to the stop timeout, for quitting and termination signals.
    func stopAllAndWait() {
        let stopping = runners.values.compactMap { runner in runner.beginStop().map { (runner, $0) } }
        let deadline = DispatchTime.now() + ToolLaunch.stopTimeout
        for (runner, child) in stopping {
            let finished = child.exited.wait(timeout: deadline) == .success
            if !finished { kill(child.process.processIdentifier, SIGKILL) }
            if !finished || child.process.terminationReason != .exit { runner.afterUncleanExit?() }
        }
    }
}

@MainActor
final class ToolRunner {
    let tool: ToolId
    private(set) var state = ToolState.off {
        didSet { if state != oldValue { onChange?() } }
    }
    /// The last status reply, nil while the tool is not running.
    private(set) var latest: ToolMessage?
    var onChange: (() -> Void)?
    var afterUncleanExit: (() -> Void)?

    private var child: Child?
    /// Whether the tool should be running, so a start while the last copy is still stopping is kept.
    private var wanted = false
    private var backoff = RestartBackoff()
    private var restart: DispatchWorkItem?
    private var nextRequestId = 1

    /// One launched copy. The pipe reader and the exit handler run on Foundation's own queues and touch only
    /// `lines` and `exited`, and `writes` owns stdin; everything else is used on the main thread.
    final class Child: @unchecked Sendable {
        let process: Process
        let input: FileHandle
        let writes = DispatchQueue(label: "com.infeace.Instantools.tool-input", qos: .utility)
        let exited = DispatchSemaphore(value: 0)
        var lines = LineBuffer()
        var stopRequested = false
        var isReady = false

        init(process: Process, input: FileHandle) {
            self.process = process
            self.input = input
        }
    }

    init(tool: ToolId) {
        self.tool = tool
    }

    func start() {
        wanted = true
        restart?.cancel()
        restart = nil
        guard child == nil else { return }
        launch()
    }

    /// Turning a tool off and on again starts its restart budget over, like trying again.
    func stop() {
        wanted = false
        restart?.cancel()
        restart = nil
        backoff.reset()
        if child == nil { state = .off }
        guard let child = beginStop() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + ToolLaunch.stopTimeout) {
            if child.process.isRunning { kill(child.process.processIdentifier, SIGKILL) }
        }
    }

    func retry() {
        backoff.reset()
        if case .failed = state { state = .off }
        start()
    }

    /// Sends SIGTERM, on which the Cmd+Tab tool restores native Cmd+Tab before exiting. Nil when nothing runs.
    func beginStop() -> Child? {
        wanted = false
        restart?.cancel()
        restart = nil
        guard let child, child.process.isRunning else { return nil }
        if !child.stopRequested {
            child.stopRequested = true
            child.process.terminate()
        }
        return child
    }

    func request(_ kind: HostRequest.Kind) {
        guard let child, child.isReady, !child.stopRequested,
              let line = MessageCoding.line(HostRequest(id: nextRequestId, request: kind))
        else { return }
        nextRequestId += 1
        // A tool that stops reading fills the pipe, and a blocked write must not freeze the menu bar.
        child.writes.async { PipeIO.write(line, to: child.input.fileDescriptor) }
    }

    private func launch() {
        let executable = Bundle.main.bundleURL.appending(path: "Contents/Helpers/\(tool.executableName)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            state = .failed("\(tool.executableName) is missing from the app. Reinstall Instantools.")
            return
        }
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment[ToolLaunch.environmentKey] = "1"
        environment[LoginItem.environmentKey] = nil
        environment[ToolLaunch.askInputMonitoringKey] = HostPreferences.isEnabled(.appSwitcher) ? "0" : "1"
        process.environment = environment
        process.qualityOfService = .userInteractive
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        // Only the tool's own ends go to it. A copy of the write end of its stdin inherited by another tool
        // would keep that stdin open after the host is gone, and the tool would never notice.
        for handle in [input.fileHandleForWriting, output.fileHandleForReading] {
            _ = fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC)
        }
        let child = Child(process: process, input: input.fileHandleForWriting)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let messages = child.lines.append(data).compactMap { MessageCoding.decode(ToolMessage.self, from: $0) }
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(messages, from: child) }
            }
        }
        process.terminationHandler = { [weak self] process in
            let reason = process.terminationReason
            let status = process.terminationStatus
            child.exited.signal()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.exited(child, reason: reason, status: status) }
            }
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            state = .failed("Could not start: \(error.localizedDescription)")
            Diagnostics.log.error("could not start \(self.tool.executableName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        self.child = child
        state = .starting
        Diagnostics.log.notice("started \(self.tool.executableName, privacy: .public), pid \(process.processIdentifier)")
    }

    private func received(_ messages: [ToolMessage], from child: Child) {
        guard child === self.child else { return }
        for message in messages {
            if message.event == .ready {
                child.isReady = true
                if !child.stopRequested { state = .running }
                // So Settings opens with data, even though it asks for fresh status only while visible.
                request(.status)
            }
            if message.appSwitcher != nil || message.layoutSwitcher != nil, message != latest {
                latest = message
                onChange?()
            }
        }
    }

    private func exited(_ child: Child, reason: Process.TerminationReason, status: Int32) {
        guard child === self.child else { return }
        self.child = nil
        latest = nil
        let asked = child.stopRequested
        if !asked || reason != .exit { afterUncleanExit?() }
        guard wanted, !asked else {
            state = .off
            if wanted { launch() }
            return
        }
        let how = reason == .uncaughtSignal ? "signal \(status)" : "status \(status)"
        Diagnostics.log.error("\(self.tool.executableName, privacy: .public) exited unexpectedly with \(how, privacy: .public)")
        switch backoff.exited(at: ProcessInfo.processInfo.systemUptime) {
        case .restart(let delay):
            state = .starting
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.wanted, self.child == nil else { return }
                    self.restart = nil
                    self.launch()
                }
            }
            restart = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        case .giveUp:
            state = .failed("Quit unexpectedly \(RestartBackoff.maxExits) times within a minute, last with \(how).")
        }
    }
}
