import AppKit
import AppSwitcherCore
import AppSwitcherKit
import InstantoolsCore
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    /// Live data comes from the host's own view of displays and permissions, and from the tools' status
    /// replies. A tool that is off has no status, and its panes show nothing live.
    struct Actions {
        var toolState: (ToolId) -> ToolState
        var isEnabled: (ToolId) -> Bool
        var setEnabled: (ToolId, Bool) -> Void
        var retry: (ToolId) -> Void
        /// Asks the running tools for their status. Replies come back through `refresh`.
        var requestStatus: () -> Void
        var appSwitcher: () -> AppSwitcherStatus?
        var layoutSwitcher: () -> LayoutSwitcherStatus?
        var displays: () -> [Display]
        var mouseDisplay: () -> UInt32?
        var accessibilityGranted: () -> Bool
        var inputMonitoringGranted: () -> Bool
    }

    struct AppChoice: Equatable {
        var bundleId: String
        var name: String
        var icon: NSImage?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.bundleId == rhs.bundleId && lhs.name == rhs.name
        }
    }

    let configStore: ConfigStore
    private(set) var toolStates: [ToolId: ToolState] = [:]
    private(set) var enabledTools: Set<ToolId> = []
    private(set) var accessibilityGranted = false
    private(set) var inputMonitoringGranted = false
    private(set) var loginEnabled = false
    private(set) var loginBlocked = false
    private(set) var loginError: String?
    private(set) var latency = LatencyStats()
    /// One refresh of the display the switcher appears on.
    private(set) var frameMilliseconds = 1000.0 / 60
    private(set) var displayName = "this display"
    private(set) var displays: [Display] = []
    private(set) var mouseDisplay: UInt32?
    private(set) var focusedDisplay: UInt32?
    private(set) var previewApps: [PreviewApp] = []
    private(set) var runningApps: [AppChoice] = []
    /// Nil until the Cmd+Tab tool has replied, false while macOS kept its own Cmd+Tab.
    private(set) var handlesCmdTab: Bool?
    private(set) var layouts: [String] = []
    /// Nil until the Language tool has replied.
    private(set) var layoutTapRunning: Bool?

    @ObservationIgnored let apps = AppLookup()
    @ObservationIgnored private let actions: Actions
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let altTabRules: [Config.Exclusion]
    @ObservationIgnored private var previewEntries: [AppSwitcherStatus.RecentApp] = []
    @ObservationIgnored private var resolved: (groups: [DisplayGroup], displays: [Display], value: ResolvedGroups)?

    init(configStore: ConfigStore, actions: Actions) {
        self.configStore = configStore
        self.actions = actions
        altTabRules = UserDefaults(suiteName: "com.lwouis.alt-tab-macos")?.string(forKey: "exceptions")
            .map(AltTabImport.exclusions(fromExceptionsJSON:)) ?? []
        refreshSystemState()
        refresh()
    }

    /// Runs only while the window is visible.
    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Common modes keep it ticking while a slider or menu is tracking the mouse.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        actions.requestStatus()
        refresh()
    }

    private func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// Assigns only what changed, so an idle window does not redraw every second.
    func refresh() {
        set(\.toolStates, Dictionary(uniqueKeysWithValues: ToolId.allCases.map { ($0, actions.toolState($0)) }))
        set(\.enabledTools, Set(ToolId.allCases.filter(actions.isEnabled)))
        let switcher = actions.appSwitcher()
        set(\.latency, LatencyStats(chronological: switcher?.latencySamples ?? []))
        set(\.focusedDisplay, switcher?.focusedDisplay)
        set(\.handlesCmdTab, switcher?.handlesCmdTab)
        let layout = actions.layoutSwitcher()
        set(\.layouts, layout?.layouts ?? [])
        set(\.layoutTapRunning, layout?.tapRunning)
        set(\.displays, actions.displays())
        set(\.mouseDisplay, actions.mouseDisplay())
        set(\.runningApps, Self.runningApps())

        // Instantools itself is listed while this window is open.
        let recent = Array((switcher?.recentApps ?? []).filter { $0.pid != ownPid }.prefix(5))
        if recent != previewEntries {
            previewEntries = recent
            previewApps = recent.compactMap { entry in
                guard let app = NSRunningApplication(processIdentifier: entry.pid), let icon = app.icon else { return nil }
                return PreviewApp(
                    id: entry.pid, name: entry.name, icon: icon, bundleId: app.bundleIdentifier,
                    state: SwitcherEntry.state(isHidden: entry.isHidden, hasWindow: entry.hasWindow)
                )
            }
        }
        let screen = NSScreen.screens.first { $0.displayId == switcherDisplay } ?? NSScreen.main
        if let screen, screen.maximumFramesPerSecond > 0 {
            set(\.frameMilliseconds, 1000.0 / Double(screen.maximumFramesPerSecond))
            set(\.displayName, screen.localizedName)
        }
    }

    /// Changed only in System Settings, and the login check is IPC, so this runs when the window becomes key.
    func refreshSystemState() {
        set(\.accessibilityGranted, actions.accessibilityGranted())
        set(\.inputMonitoringGranted, actions.inputMonitoringGranted())
        set(\.loginEnabled, LoginItem.isEnabled)
        set(\.loginBlocked, LoginItem.isBlockedInLoginItems)
    }

    private var switcherDisplay: UInt32? {
        configStore.config.scope == .focusedDisplay ? focusedDisplay ?? mouseDisplay : mouseDisplay
    }

    func binding<Value: Equatable>(_ keyPath: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(
            get: { self.configStore.config[keyPath: keyPath] },
            set: { value in self.configStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    func state(of tool: ToolId) -> ToolState {
        toolStates[tool] ?? .off
    }

    func isEnabled(_ tool: ToolId) -> Bool {
        enabledTools.contains(tool)
    }

    func enabled(_ tool: ToolId) -> Binding<Bool> {
        Binding(
            get: { self.enabledTools.contains(tool) },
            set: { enabled in
                self.actions.setEnabled(tool, enabled)
                self.refresh()
            }
        )
    }

    func retry(_ tool: ToolId) {
        actions.retry(tool)
        refresh()
    }

    /// Cmd+Tab goes to Instantools right now.
    var switcherActive: Bool {
        state(of: .appSwitcher) == .running && handlesCmdTab != false
    }

    /// Accessibility lets Language listen too, so Input Monitoring is only missing without it.
    var needsInputMonitoring: Bool {
        isEnabled(.layoutSwitcher) && !accessibilityGranted && !inputMonitoringGranted
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
                self.refreshSystemState()
            }
        )
    }

    var runningAppsToPassThrough: [AppChoice] {
        runningApps.filter { !configStore.config.passesThrough($0.bundleId) }
    }

    func addPassThrough(_ bundleIds: [String]) {
        configStore.update { config in
            for bundleId in bundleIds where !config.passesThrough(bundleId) { config.passThrough.append(bundleId) }
        }
    }

    func removePassThrough(_ bundleId: String) {
        configStore.update { $0.passThrough.removeAll { $0 == bundleId } }
    }

    var runningAppsToExclude: [AppChoice] {
        let excluded = Set(configStore.config.exclude.map { $0.bundleId.lowercased() })
        return runningApps.filter { !excluded.contains($0.bundleId.lowercased()) }
    }

    private static func runningApps() -> [AppChoice] {
        let own = Bundle.main.bundleIdentifier?.lowercased()
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> AppChoice? in
                guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier else { return nil }
                let key = bundleId.lowercased()
                guard key != own, seen.insert(key).inserted else { return nil }
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
        let rules = chooseApps(title: "Choose Apps to Exclude", prompt: "Exclude").map { Config.Exclusion(bundleId: $0) }
        configStore.update { $0.addExclusions(rules) }
    }

    func chooseAppsToPassThrough() {
        addPassThrough(chooseApps(title: "Choose Apps That Keep Cmd+Tab", prompt: "Add"))
    }

    /// Bundle ids of apps picked from Applications.
    func chooseApps(title: String, prompt: String, multiple: Bool = true) -> [String] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    func bindAppKey(_ key: Character, to bundleId: String, replacing current: Character? = nil) {
        configStore.update { $0.bindAppKey(key, to: bundleId, replacing: current) }
    }

    func removeAppKey(_ key: Character) {
        configStore.update { $0.appKeys.removeAll { $0.key == key } }
    }

    static let groupColors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .yellow, .red]

    var groups: [DisplayGroup] { configStore.config.displayGroups }

    func color(ofGroup name: String) -> Color {
        let index = groups.firstIndex { $0.name == name } ?? 0
        return Self.groupColors[index % Self.groupColors.count]
    }

    /// Resolved once per change of groups or displays rather than on every render.
    var resolvedGroups: ResolvedGroups {
        let groups = groups
        let displays = displays
        if let resolved, resolved.groups == groups, resolved.displays == displays { return resolved.value }
        let value = ResolvedGroups(groups, displays: displays)
        resolved = (groups, displays, value)
        return value
    }

    func groupColors(of display: Display) -> [Color] {
        resolvedGroups.groups.filter { $0.members.contains(display.id) }.map { color(ofGroup: $0.name) }
    }

    func members(of group: DisplayGroup) -> Set<UInt32> {
        resolvedGroups.members(of: group.name) ?? []
    }

    /// What Cmd+Tab would list right now.
    var currentTargets: Set<UInt32>? {
        DisplayScope.targets(
            for: configStore.config.scope, groups: resolvedGroups,
            mouseDisplay: mouseDisplay, focusedDisplay: focusedDisplay
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

    func openRepository() {
        if let url = URL(string: "https://github.com/infeace/Instantools") { NSWorkspace.shared.open(url) }
    }
}

extension [Display] {
    func names(of ids: Set<UInt32>) -> String {
        let names = filter { ids.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No monitor connected" : names.formatted(.list(type: .and))
    }
}
