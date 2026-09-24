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
        var displays: () -> [Display]
        var mouseDisplay: () -> UInt32?
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
    private(set) var displays: [Display] = []
    private(set) var mouseDisplay: UInt32?

    @ObservationIgnored let apps = AppLookup()
    @ObservationIgnored private let actions: Actions
    @ObservationIgnored private var timer: Timer?
    /// AltTab's hide rules, read once when Settings opens.
    @ObservationIgnored private let altTabRules: [Config.Exclusion]

    init(configStore: ConfigStore, actions: Actions) {
        self.configStore = configStore
        self.actions = actions
        altTabRules = UserDefaults(suiteName: "com.lwouis.alt-tab-macos")?.string(forKey: "exceptions")
            .map(AltTabImport.exclusions(fromExceptionsJSON:)) ?? []
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
        let displays = actions.displays()
        if displays != self.displays { self.displays = displays }
        let mouse = actions.mouseDisplay()
        if mouse != mouseDisplay { mouseDisplay = mouse }
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

    // MARK: Excluded apps

    struct AppChoice {
        var bundleId: String
        var name: String
        var icon: NSImage?
    }

    /// Running apps that are not excluded yet, by name.
    var runningAppsToExclude: [AppChoice] {
        let excluded = Set(configStore.config.exclude.map { $0.bundleId.lowercased() })
        let own = Bundle.main.bundleIdentifier?.lowercased()
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> AppChoice? in
                guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier else { return nil }
                let key = bundleId.lowercased()
                guard key != own, !excluded.contains(key), seen.insert(key).inserted else { return nil }
                return AppChoice(bundleId: bundleId, name: app.localizedName ?? bundleId, icon: app.icon)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var altTabRulesToImport: [Config.Exclusion] {
        let excluded = Set(configStore.config.exclude.map { $0.bundleId.lowercased() })
        return altTabRules.filter { !excluded.contains($0.bundleId.lowercased()) }
    }

    func exclude(_ bundleId: String) {
        configStore.update { $0.addExclusions([.init(bundleId: bundleId)]) }
    }

    func removeExclusion(_ bundleId: String) {
        configStore.update { $0.exclude.removeAll { $0.bundleId == bundleId } }
    }

    func importAltTab() {
        let rules = altTabRulesToImport
        configStore.update { $0.addExclusions(rules) }
    }

    func exclusionWhen(_ bundleId: String) -> Binding<Config.Exclusion.When> {
        Binding(
            get: { self.configStore.config.exclude.first { $0.bundleId == bundleId }?.when ?? .always },
            set: { when in
                self.configStore.update { config in
                    guard let index = config.exclude.firstIndex(where: { $0.bundleId == bundleId }) else { return }
                    config.exclude[index].when = when
                }
            }
        )
    }

    func chooseAppsToExclude() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Exclude"
        panel.prompt = "Exclude"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let rules = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.map { Config.Exclusion(bundleId: $0) }
        configStore.update { $0.addExclusions(rules) }
    }

    // MARK: Monitors

    static let groupColors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .yellow, .red]

    var groups: [DisplayGroup] { configStore.config.displayGroups }

    func color(ofGroup name: String) -> Color {
        let index = groups.firstIndex { $0.name == name } ?? 0
        return Self.groupColors[index % Self.groupColors.count]
    }

    /// Group colors for the groups a display is in, in group order.
    func groupColors(of display: Display) -> [Color] {
        groups.filter { $0.members(in: displays).contains(display.id) }.map { color(ofGroup: $0.name) }
    }

    /// The displays Cmd+Tab would list apps from right now. The focused window is taken to be
    /// under the mouse, since Settings itself has focus while it is open.
    var currentTargets: Set<UInt32>? {
        DisplayScope.targets(
            for: configStore.config.scope, groups: ResolvedGroups(groups, displays: displays),
            mouseDisplay: mouseDisplay, focusedDisplay: mouseDisplay
        )
    }

    var scopeOptions: [Config.Scope] {
        var options: [Config.Scope] = [.all, .mouseDisplay, .focusedDisplay, .mouseGroup] + groups.map { .group($0.name) }
        if !options.contains(configStore.config.scope) { options.append(configStore.config.scope) }
        return options
    }

    func saveGroup(_ group: DisplayGroup, replacing originalName: String?) {
        configStore.update { config in
            if let originalName, let index = config.displayGroups.firstIndex(where: { $0.name == originalName }) {
                config.displayGroups[index] = group
                if config.scope == .group(originalName) { config.scope = .group(group.name) }
            } else {
                config.displayGroups.append(group)
            }
        }
    }

    func deleteGroup(_ name: String) {
        configStore.update { config in
            config.displayGroups.removeAll { $0.name == name }
            if config.scope == .group(name) { config.scope = .all }
        }
    }

    func newGroupName() -> String {
        let names = Set(groups.map(\.name))
        return (1...).lazy.map { $0 == 1 ? "New Group" : "New Group \($0)" }.first { !names.contains($0) }!
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
