import AppKit
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit

/// Runs each enabled tool as a child process. Tools are started only here, with Process: macOS then treats
/// them as part of Instantools, so they share its permissions. Opened through LaunchServices or launchd they
/// would be apps of their own, each with its own permission prompts.
@MainActor
final class ToolSupervisor {
    /// Where the native Cmd+Tab marker is kept: the host's defaults, or memory in tests.
    @MainActor
    struct MarkerStore {
        var load: () -> NativeSwitcherMarker
        var save: (NativeSwitcherMarker) -> Void

        static var hostPreferences: MarkerStore {
            MarkerStore(load: { HostPreferences.nativeSwitcher }, save: { HostPreferences.nativeSwitcher = $0 })
        }
    }

    private var runners: [ToolId: ToolRunner] = [:]
    private let marker: MarkerStore
    var onChange: (() -> Void)?

    /// `helpers` and `marker` are for tests.
    init(helpers: URL = Bundle.main.bundleURL.appending(path: "Contents/Helpers"), marker: MarkerStore = .hostPreferences) {
        self.marker = marker
        for tool in ToolId.allCases {
            let runner = ToolRunner(tool: tool, helpers: helpers)
            runner.onChange = { [weak self] in self?.onChange?() }
            runners[tool] = runner
        }
        let switcher = runners[.appSwitcher]
        switcher?.willLaunch = { [weak self] in self?.editMarker { $0.startingSwitcher() } }
        switcher?.didFailToLaunch = { [weak self] in self?.editMarker { $0.switcherFailedToStart() } }
        // The tool restores native Cmd+Tab on its own way out. A kill or a crash it could not handle skips
        // that, so the host does it before anything else.
        switcher?.didExit = { [weak self] asked, normally in
            self?.updateNativeSwitcher { $0.switcherExited(asked: asked, normally: normally) }
        }
    }

    /// At launch, before any tool starts. InstantTab turns native Cmd+Tab off again as it starts.
    func recoverNativeSwitcher(stoppedLeftoverSwitcher: Bool) {
        updateNativeSwitcher { $0.launched(stoppedLeftoverSwitcher: stoppedLeftoverSwitcher) }
    }

    /// Restores before the cleared marker is saved, so a host that dies in between restores at its next launch.
    private func updateNativeSwitcher(_ step: (inout NativeSwitcherMarker) -> Bool) {
        var current = marker.load()
        if step(&current) { NativeSwitcher.restore() }
        marker.save(current)
    }

    private func editMarker(_ edit: (inout NativeSwitcherMarker) -> Void) {
        var current = marker.load()
        edit(&current)
        marker.save(current)
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

    /// Blocks for up to the stop timeout, for quitting and termination signals. Native Cmd+Tab is restored
    /// whenever InstantTab may have left it off, even if it was just turned off: a tool killed here or just
    /// before never has its exit handled once the host exits. Otherwise the setting may belong to another
    /// switcher.
    func stopAllAndWait() {
        let switcherWasRunning = runners[.appSwitcher]?.hasChild ?? false
        let stopping = runners.values.compactMap { $0.beginStop() }
        let deadline = DispatchTime.now() + ToolLaunch.stopTimeout
        for child in stopping where child.exited.wait(timeout: deadline) != .success {
            kill(child.process.processIdentifier, SIGKILL)
        }
        updateNativeSwitcher { $0.quitting(switcherWasRunning: switcherWasRunning) }
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
    var willLaunch: (() -> Void)?
    /// After `willLaunch`, when the process could not be started.
    var didFailToLaunch: (() -> Void)?
    /// Whether the host asked it to stop, and whether it exited through `exit()` rather than a signal.
    var didExit: ((_ asked: Bool, _ normally: Bool) -> Void)?

    private var child: Child?
    /// Whether the tool should be running, so a start while the last copy is still stopping is kept.
    private var wanted = false
    private var backoff = RestartBackoff()
    private var restart: DispatchWorkItem?

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

    private let helpers: URL

    init(tool: ToolId, helpers: URL) {
        self.tool = tool
        self.helpers = helpers
    }

    /// Also while it is stopping, and after it exited until the main thread has handled that.
    var hasChild: Bool {
        child != nil
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
              let line = MessageCoding.line(HostRequest(request: kind))
        else { return }
        // A tool that stops reading fills the pipe, and a blocked write must not freeze the menu bar.
        child.writes.async { PipeIO.write(line, to: child.input.fileDescriptor) }
    }

    private func launch() {
        let executable = helpers.appending(path: tool.executableName)
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
        willLaunch?()
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            didFailToLaunch?()
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
            if message.event == nil, message != latest {
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
        didExit?(asked, reason == .exit)
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
