import AppKit
import InstantTabCore
import Observation

/// Settings edits apply at once and reach the file shortly after, so a dragged slider writes once. While
/// the file does not parse, the last good config stays in use and Settings cannot overwrite it.
@MainActor
@Observable
final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/instanttab")
    static let fileURL = directory.appending(path: "config.json5")

    private(set) var config = Config()
    private(set) var error: String?
    private(set) var warnings: [String] = []
    private(set) var fileIsBroken = false
    @ObservationIgnored var onChange: ((Config) -> Void)?

    @ObservationIgnored private var directorySource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
    }

    func start() {
        load()
        directorySource = watch(Self.directory.path, events: .write)
        watchFile()
    }

    func update(_ edit: (inout Config) -> Void) {
        guard !fileIsBroken else { return }
        var next = config
        edit(&next)
        guard next != config else { return }
        config = next
        onChange?(next)
        scheduleSave()
    }

    /// Also replaces a file that does not parse, since the user asked for defaults.
    func resetToDefaults() {
        fileIsBroken = false
        error = nil
        warnings = []
        if config != Config() {
            config = Config()
            onChange?(config)
        }
        scheduleSave()
        flush()
    }

    func flush() {
        guard saveWork != nil else { return }
        save()
    }

    func load() {
        // Edits still waiting to be saved are newer than the file.
        guard saveWork == nil else { return }
        // A deleted file comes back with the defaults, as on first launch.
        createDefaultFileIfMissing()
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            error = "cannot read \(Self.fileURL.path)"
            fileIsBroken = true
            return
        }
        do {
            let parsed = try Config.parse(data)
            error = nil
            fileIsBroken = false
            warnings = parsed.warnings
            for warning in warnings { Diagnostics.log.warning("config: \(warning, privacy: .public)") }
            if parsed.config != config {
                config = parsed.config
                onChange?(config)
            }
        } catch {
            self.error = error.description
            fileIsBroken = true
            Diagnostics.log.error("config: \(error.description, privacy: .public)")
        }
    }

    /// `.json5` has no default app on most Macs, so TextEdit is the fallback.
    func openInEditor() {
        flush()
        if NSWorkspace.shared.urlForApplication(toOpen: Self.fileURL) != nil {
            NSWorkspace.shared.open(Self.fileURL)
        } else {
            NSWorkspace.shared.open(
                [Self.fileURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    func revealInFinder() {
        flush()
        NSWorkspace.shared.activateFileViewerSelecting([Self.fileURL])
    }

    private func scheduleSave() {
        guard persists else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.save() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    private func save() {
        saveWork?.cancel()
        saveWork = nil
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try Data(config.fileContents.utf8).write(to: Self.fileURL, options: .atomic)
        } catch {
            self.error = "cannot save: \(error.localizedDescription)"
            Diagnostics.log.error("config save: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createDefaultFileIfMissing() {
        let manager = FileManager.default
        guard persists, !manager.fileExists(atPath: Self.fileURL.path) else { return }
        try? manager.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? Config.defaultFileContents.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }

    /// Editors often save by replacing the file, so the directory is watched too and the file watch re-armed.
    private func watchFile() {
        fileSource?.cancel()
        fileSource = watch(Self.fileURL.path, events: [.write, .extend, .delete, .rename, .attrib])
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.watchFile()
                self?.load()
            }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }
}
