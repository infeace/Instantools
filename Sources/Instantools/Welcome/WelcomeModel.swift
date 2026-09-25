import Foundation
import InstantoolsCore
import InstantoolsKit
import Observation

/// Choosing the tools applies them on Continue, the way Settings' switches do, and Start at login applies on
/// finishing, so closing the window early keeps only what was applied so far.
@MainActor
@Observable
final class WelcomeModel {
    struct Actions {
        var isEnabled: (ToolId) -> Bool
        var setEnabled: (ToolId, Bool) -> Void
        /// Runs off the main thread, since the Input Monitoring check takes 10 to 28 ms.
        var permissions: @Sendable () -> PermissionState
        var setStartAtLogin: (Bool) throws -> Void
        var openSettings: () -> Void
    }

    private(set) var step: WelcomeStep {
        didSet { updatePolling() }
    }
    var chosen = Set(ToolId.allCases)
    /// Nil until the first check is back.
    private(set) var permissions: PermissionState?
    var startAtLogin = true
    private(set) var loginError: String?

    @ObservationIgnored var close: () -> Void = {}
    /// Nothing is checked while the window is minimized, hidden or covered.
    @ObservationIgnored var isVisible = true {
        didSet { updatePolling() }
    }
    @ObservationIgnored private let actions: Actions
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var checking = false

    init(actions: Actions, step: WelcomeStep = .tools) {
        self.actions = actions
        self.step = step
        checkPermissions()
        updatePolling()
    }

    var needs: [PermissionNeed] {
        (permissions ?? PermissionState(accessibility: false, inputMonitoring: false)).needed(by: chosen)
    }

    func isChosen(_ tool: ToolId) -> Bool {
        chosen.contains(tool)
    }

    func toggle(_ tool: ToolId) {
        if chosen.remove(tool) == nil { chosen.insert(tool) }
    }

    func goOn() {
        if step == .tools {
            for tool in ToolId.allCases where isChosen(tool) != actions.isEnabled(tool) {
                actions.setEnabled(tool, isChosen(tool))
            }
        }
        if let next = step.next(choosing: chosen) { step = next }
    }

    func goBack() {
        loginError = nil
        if let previous = step.previous(choosing: chosen) { step = previous }
    }

    func finish(openingSettings: Bool) {
        do {
            try actions.setStartAtLogin(startAtLogin)
        } catch {
            loginError = error.localizedDescription
            return
        }
        close()
        if openingSettings { actions.openSettings() }
    }

    /// A check that outlasts the interval is not overlapped by the next.
    func checkPermissions() {
        guard !checking else { return }
        checking = true
        PermissionPoll.check(actions.permissions) { [weak self] state in
            guard let self else { return }
            checking = false
            if permissions != state { permissions = state }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Answering a prompt or flipping a switch in System Settings changes the status, so it is polled while
    /// the step shows it.
    private func updatePolling() {
        guard step == .permissions, isVisible else { return stop() }
        guard timer == nil else { return }
        checkPermissions()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
