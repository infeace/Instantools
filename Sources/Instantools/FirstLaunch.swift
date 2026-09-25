import AppKit
import AppSwitcherCore
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit

/// Takes over from the standalone InstantTab and InstantLang apps once, and their Start at login again after
/// any install that removes their login agents. The old apps and their config are never moved or deleted, so
/// either can be started again to go back.
@MainActor
enum FirstLaunch {
    private static let doneKey = "firstLaunchDone"
    /// Written by `scripts/build.sh --install`, which removes the old login agents before this runs.
    private static let removedAgentsKey = "removedOldLoginAgents"
    private static let configCopyPendingKey = "oldConfigCopyPending"
    static let oldConfigURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/instanttab/config.json5")

    /// True when nothing was carried over, so the welcome should open to choose the tools.
    static func runIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else {
            takeOverRemovedAgents()
            retryConfigCopy()
            return false
        }
        let plan = Migration.plan(for: facts())
        Diagnostics.log.notice("first launch: \(String(describing: plan), privacy: .public)")

        if plan.copyOldConfig, !copyOldConfig() { defaults.set(true, forKey: configCopyPendingKey) }
        for app in plan.agentsToRemove {
            bootOut(app.agentLabel)
            try? FileManager.default.removeItem(at: LoginItem.agentURL(label: app.agentLabel))
        }
        if !plan.enableStartAtLogin || enableStartAtLogin() {
            defaults.removeObject(forKey: removedAgentsKey)
        } else {
            // Their plists were just removed, so only this tells the next launch to try again.
            defaults.set(plan.agentsToRemove.map(\.rawValue), forKey: removedAgentsKey)
        }
        HostPreferences.enabledTools = plan.enabledTools
        defaults.set(true, forKey: doneKey)
        return plan.showWelcome
    }

    /// An install after the first launch can remove an old app's login agent too, when someone went back to
    /// it, and then nothing would start at login.
    private static func takeOverRemovedAgents() {
        let defaults = UserDefaults.standard
        let removed = defaults.stringArray(forKey: removedAgentsKey) ?? []
        guard !removed.isEmpty else { return }
        Diagnostics.log.notice("install removed login agents of \(removed.joined(separator: ", "), privacy: .public)")
        if enableStartAtLogin() { defaults.removeObject(forKey: removedAgentsKey) }
    }

    private static func enableStartAtLogin() -> Bool {
        do {
            try LoginItem.setEnabled(true)
            return true
        } catch {
            Diagnostics.log.error("could not turn on Start at login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Written in one step, so a failure never leaves part of a file, and a retry replaces the defaults.
    private static func copyOldConfig() -> Bool {
        do {
            let data = try Data(contentsOf: oldConfigURL)
            try FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
            try data.write(to: ConfigStore.writeTarget(for: ConfigStore.fileURL), options: .atomic)
            return true
        } catch {
            Diagnostics.log.error("could not copy the standalone InstantTab app's config: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// A copy that failed at the first launch is tried again, before the config store starts, only while the
    /// config is still the defaults the host wrote, so edits made since are never replaced.
    private static func retryConfigCopy() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: configCopyPendingKey),
              let current = try? Data(contentsOf: ConfigStore.fileURL)
        else { return }
        let customized = current != Data(Config.defaultFileContents.utf8)
        let gone = !FileManager.default.fileExists(atPath: oldConfigURL.path)
        if customized || gone || copyOldConfig() {
            defaults.removeObject(forKey: configCopyPendingKey)
        }
    }

    private static func facts() -> Migration.Facts {
        let files = FileManager.default
        let applications = files.homeDirectoryForCurrentUser.appending(path: "Applications")
        let removedAgents = Set((UserDefaults.standard.stringArray(forKey: removedAgentsKey) ?? []).compactMap(Migration.OldApp.init(rawValue:)))
        let apps = Migration.OldApp.allCases
        return Migration.Facts(
            newConfigExists: files.fileExists(atPath: ConfigStore.fileURL.path),
            oldConfigExists: files.fileExists(atPath: oldConfigURL.path),
            loginAgents: Set(apps.filter { files.fileExists(atPath: LoginItem.agentURL(label: $0.agentLabel).path) }).union(removedAgents),
            installed: Set(apps.filter { files.fileExists(atPath: applications.appending(path: "\($0.rawValue).app").path) }),
            running: Set(apps.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleId).isEmpty })
        )
    }

    /// Also stops the old app when the agent started it. Failing is fine: the agent may not be loaded.
    private static func bootOut(_ label: String) {
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        launchctl.standardOutput = FileHandle.nullDevice
        launchctl.standardError = FileHandle.nullDevice
        do {
            try launchctl.run()
            launchctl.waitUntilExit()
        } catch {
            Diagnostics.log.error("launchctl bootout \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
