import ServiceManagement

/// Start at login through a bundled launch agent that relaunches InstantTab if it crashes (so native
/// Cmd+Tab is not left off), falling back to a plain login item if the agent cannot be registered.
@MainActor
enum LoginItem {
    private static let agent = SMAppService.agent(plistName: "com.infeace.InstantTab.agent.plist")

    static var isEnabled: Bool {
        agent.status == .enabled || SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        agent.status == .requiresApproval || SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try agent.register()
            } catch {
                Diagnostics.log.error("launch agent registration failed: \(error.localizedDescription, privacy: .public)")
                // Waiting for approval is not a failure; registering both would start two copies at login.
                guard agent.status != .requiresApproval else { return }
                try SMAppService.mainApp.register()
            }
        } else {
            if agent.status != .notRegistered { try agent.unregister() }
            if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
