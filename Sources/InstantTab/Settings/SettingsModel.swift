import AppKit
import InstantTabCore
import Observation
import SwiftUI

/// State and actions behind the Settings window. Lives only while the window is open.
@MainActor
@Observable
final class SettingsModel {
    struct Actions {
        var isPaused: () -> Bool
        var setPaused: (Bool) -> Void
        var latency: () -> LatencyStats
    }

    let configStore: ConfigStore
    private(set) var isPaused = false
    private(set) var accessibilityGranted = false
    private(set) var loginEnabled = false
    private(set) var loginNeedsApproval = false
    private(set) var loginError: String?
    private(set) var latency = LatencyStats()
    /// One refresh of the main display, to put draw time in context.
    private(set) var frameMilliseconds = 1000.0 / 60
    private(set) var displayName = "this display"

    @ObservationIgnored private let actions: Actions
    @ObservationIgnored private var timer: Timer?

    init(configStore: ConfigStore, actions: Actions) {
        self.configStore = configStore
        self.actions = actions
        refresh()
    }

    /// Permissions, login state and draw time change outside the app, so they are re-read while open.
    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        isPaused = actions.isPaused()
        accessibilityGranted = Permissions.accessibility
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
        latency = actions.latency()
        if let screen = NSScreen.main, screen.maximumFramesPerSecond > 0 {
            frameMilliseconds = 1000.0 / Double(screen.maximumFramesPerSecond)
            displayName = screen.localizedName
        }
    }

    // MARK: Bindings

    /// A binding to one config value. Setting it applies at once and saves to the file.
    func binding<Value: Equatable>(_ keyPath: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(
            get: { self.configStore.config[keyPath: keyPath] },
            set: { value in self.configStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    var enabled: Binding<Bool> {
        Binding(
            get: { !self.isPaused },
            set: { enabled in
                self.actions.setPaused(!enabled)
                self.refresh()
            }
        )
    }

    var startAtLogin: Binding<Bool> {
        Binding(
            get: { self.loginEnabled },
            set: { enabled in self.setLoginEnabled(enabled) }
        )
    }

    // MARK: Actions

    func grantAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    func openLoginItemsSettings() {
        LoginItem.openSettings()
    }

    func openConfigFile() {
        configStore.flush()
        NSWorkspace.shared.open(ConfigStore.fileURL)
    }

    func revealConfigFile() {
        configStore.flush()
        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
    }

    private func setLoginEnabled(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            Diagnostics.log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
        if loginNeedsApproval { LoginItem.openSettings() }
    }
}
