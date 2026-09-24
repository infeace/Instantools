import Foundation
import InstantTabCore
import Observation

/// Loads `~/.config/instanttab/config.json5`, writes the documented defaults on first launch, and
/// reloads on save. Settings edits apply in memory at once and reach the file shortly after, so a
/// dragged slider writes once. A broken file keeps the last good config and reports the error.
@MainActor
@Observable
final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/instanttab")
    static let fileURL = directory.appending(path: "config.json5")

    private(set) var config = Config()
    private(set) var error: String?
    private(set) var warnings: [String] = []
    @ObservationIgnored var onChange: ((Config) -> Void)?

    @ObservationIgnored private var directorySource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    /// What this process last wrote, so its own save is not read back as an outside edit.
    @ObservationIgnored private var lastWritten: Data?

    func start() {
        createDefaultFileIfMissing()
        load()
        directorySource = watch(Self.directory.path, events: .write)
        watchFile()
    }

    /// Applies an edit from Settings now and saves it to the file shortly after.
    func update(_ edit: (inout Config) -> Void) {
        var next = config
        edit(&next)
        guard next != config else { return }
        config = next
        onChange?(next)
        scheduleSave()
    }

    /// Writes any pending edit immediately, for quitting.
    func flush() {
        guard saveWork != nil else { return }
        save()
    }

    func load() {
        // Unsaved edits from Settings are newer than the file.
        guard saveWork == nil else { return }
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            error = "cannot read \(Self.fileURL.path)"
            return
        }
        guard data != lastWritten else { return }
        do {
            let parsed = try Config.parse(data)
            error = nil
            warnings = parsed.warnings
            for warning in warnings { Diagnostics.log.warning("config: \(warning, privacy: .public)") }
            if parsed.config != config {
                config = parsed.config
                onChange?(config)
            }
        } catch {
            self.error = error.description
            Diagnostics.log.error("config: \(error.description, privacy: .public)")
        }
    }

    private func scheduleSave() {
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
        let data = Data(config.fileContents.utf8)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try data.write(to: Self.fileURL, options: .atomic)
            lastWritten = data
            error = nil
            warnings = []
        } catch {
            self.error = "cannot save: \(error.localizedDescription)"
            Diagnostics.log.error("config save: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createDefaultFileIfMissing() {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: Self.fileURL.path) else { return }
        try? manager.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? Config.defaultFileContents.write(to: Self.fileURL, atomically: true, encoding: .utf8)
    }

    /// Editors often save by replacing the file, so the directory is watched too and the file watch is re-armed.
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
