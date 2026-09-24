import Foundation
import InstantTabCore

/// Loads `~/.config/instanttab/config.json5`, writes the documented defaults on first launch, and
/// reloads on save. A broken file keeps the last good config and reports the error in the menu.
@MainActor
final class ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/instanttab")
    static let fileURL = directory.appending(path: "config.json5")

    private(set) var config = Config()
    private(set) var error: String?
    private(set) var warnings: [String] = []
    var onChange: ((Config) -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?

    func start() {
        createDefaultFileIfMissing()
        load()
        directorySource = watch(Self.directory.path, events: .write)
        watchFile()
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            error = "cannot read \(Self.fileURL.path)"
            return
        }
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
