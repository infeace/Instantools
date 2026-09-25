import AppKit
import AppSwitcherKit
import InstantoolsCore
import InstantoolsKit

/// Takes over from InstantTab and InstantLang once, and their Start at login again after any install that
/// removes their login agents. The old apps and their config are never moved or deleted, so either can be
/// started again to go back.
@MainActor
enum FirstLaunch {
    private static let doneKey = "firstLaunchDone"
    /// Written by `scripts/build.sh --install`, which removes the old login agents before this runs.
    private static let removedAgentsKey = "removedOldLoginAgents"
    static let oldConfigURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/instanttab/config.json5")

    /// True when nothing was carried over, so Settings should open to choose the tools.
    static func runIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else {
            takeOverRemovedAgents()
            return false
        }
        let plan = Migration.plan(for: facts())
        Diagnostics.log.notice("first launch: \(String(describing: plan), privacy: .public)")

        if plan.copyOldConfig {
            do {
                try FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: oldConfigURL, to: ConfigStore.fileURL)
            } catch {
                Diagnostics.log.error("could not copy the InstantTab config: \(error.localizedDescription, privacy: .public)")
            }
        }
        for app in plan.agentsToRemove {
            bootOut(app.agentLabel)
            try? FileManager.default.removeItem(at: LoginItem.agentURL(label: app.agentLabel))
        }
        if plan.enableStartAtLogin { enableStartAtLogin() }
        HostPreferences.enabledTools = plan.enabledTools
        defaults.removeObject(forKey: removedAgentsKey)
        defaults.set(true, forKey: doneKey)
        return plan.showSettings
    }

    /// An install after the first launch can remove an old app's login agent too, when someone went back to
    /// it, and then nothing would start at login.
    private static func takeOverRemovedAgents() {
        let defaults = UserDefaults.standard
        let removed = defaults.stringArray(forKey: removedAgentsKey) ?? []
        guard !removed.isEmpty else { return }
        Diagnostics.log.notice("install removed login agents of \(removed.joined(separator: ", "), privacy: .public)")
        enableStartAtLogin()
        defaults.removeObject(forKey: removedAgentsKey)
    }

    private static func enableStartAtLogin() {
        do {
            try LoginItem.setEnabled(true)
        } catch {
            Diagnostics.log.error("could not turn on Start at login: \(error.localizedDescription, privacy: .public)")
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
