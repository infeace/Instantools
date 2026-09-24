import AppKit
import InstantTabCore
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    struct Actions {
        var isPaused: () -> Bool
        var setPaused: (Bool) -> Void
        var latency: () -> LatencyStats
        var displays: () -> [Display]
        var mouseDisplay: () -> UInt32?
        var accessibilityGranted: () -> Bool
        /// Most recently used first, without excluded apps.
        var recentApps: () -> [Int32]
    }

    struct AppChoice: Equatable {
        var bundleId: String
        var name: String
        var icon: NSImage?
    }

    let configStore: ConfigStore
    private(set) var isPaused = false
    private(set) var accessibilityGranted = false
    private(set) var loginEnabled = false
    private(set) var loginBlocked = false
    private(set) var loginError: String?
    private(set) var latency = LatencyStats()
    /// One refresh of the display under the mouse, where the switcher appears.
    private(set) var frameMilliseconds = 1000.0 / 60
    private(set) var displayName = "this display"
    private(set) var displays: [Display] = []
    private(set) var mouseDisplay: UInt32?
    private(set) var previewApps: [PreviewApp] = []
    private(set) var runningAppsToExclude: [AppChoice] = []

    @ObservationIgnored let apps = AppLookup()
    @ObservationIgnored private let actions: Actions
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let altTabRules: [Config.Exclusion]

    init(configStore: ConfigStore, actions: Actions) {
        self.configStore = configStore
        self.actions = actions
        altTabRules = UserDefaults(suiteName: "com.lwouis.alt-tab-macos")?.string(forKey: "exceptions")
            .map(AltTabImport.exclusions(fromExceptionsJSON:)) ?? []
        refresh()
    }

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

    /// Assigns only what changed, so an idle window does not redraw every second.
    func refresh() {
        func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Value>, _ value: Value) {
            if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
        }
        set(\.isPaused, actions.isPaused())
        set(\.accessibilityGranted, actions.accessibilityGranted())
        set(\.loginEnabled, LoginItem.isEnabled)
        set(\.loginBlocked, LoginItem.isBlockedInLoginItems)
        set(\.latency, actions.latency())
        set(\.displays, actions.displays())
        set(\.mouseDisplay, actions.mouseDisplay())
        set(\.runningAppsToExclude, Self.runningApps(excluding: configStore.config.exclude))

        let recent = Array(actions.recentApps().prefix(5))
        if recent != previewApps.map(\.id) {
            previewApps = recent.compactMap { pid in
                guard let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon else { return nil }
                return PreviewApp(id: pid, name: app.localizedName ?? "App", icon: icon)
            }
        }
        let screen = NSScreen.screens.first { $0.displayId == mouseDisplay } ?? NSScreen.main
        if let screen, screen.maximumFramesPerSecond > 0 {
            set(\.frameMilliseconds, 1000.0 / Double(screen.maximumFramesPerSecond))
            set(\.displayName, screen.localizedName)
        }
    }

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
            set: { enabled in
                do {
                    try LoginItem.setEnabled(enabled)
                    self.loginError = nil
                } catch {
                    self.loginError = error.localizedDescription
                }
                self.refresh()
            }
        )
    }

    private static func runningApps(excluding exclusions: [Config.Exclusion]) -> [AppChoice] {
        let excluded = Set(exclusions.map { $0.bundleId.lowercased() })
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
        refresh()
    }

    func removeExclusion(_ bundleId: String) {
        configStore.update { $0.exclude.removeAll { $0.bundleId == bundleId } }
        refresh()
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
        refresh()
    }

    static let groupColors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .yellow, .red]

    var groups: [DisplayGroup] { configStore.config.displayGroups }

    func color(ofGroup name: String) -> Color {
        let index = groups.firstIndex { $0.name == name } ?? 0
        return Self.groupColors[index % Self.groupColors.count]
    }

    func groupColors(of display: Display) -> [Color] {
        groups.filter { $0.members(in: displays).contains(display.id) }.map { color(ofGroup: $0.name) }
    }

    /// What Cmd+Tab would list right now. Settings has focus while open, so the focused window is taken
    /// to be under the mouse.
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

    func displayNames(_ ids: Set<UInt32>, empty: String) -> String {
        let names = displays.filter { ids.contains($0.id) }.map(\.name)
        return names.isEmpty ? empty : names.formatted(.list(type: .and))
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

    func grantAccessibility() {
        Permissions.requestAccessibilityInSettings()
    }

    func resetAll() {
        configStore.resetToDefaults()
    }

    func openRepository() {
        if let url = URL(string: "https://github.com/infeace/InstantTab") { NSWorkspace.shared.open(url) }
    }
}
