import AppKit
import AppSwitcherCore
import InstantoolsKit
import Observation

/// Settings edits apply at once and reach the file shortly after, so a dragged slider writes once. While
/// the file does not parse, the last good config stays in use and Settings cannot overwrite it. Only the
/// host writes the file; the Cmd+Tab tool reads it with `persists` off and follows every change.
@MainActor
@Observable
public final class ConfigStore {
    /// Named for Instantools rather than Cmd+Tab, so other tools can keep their files beside this one.
    public static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/instantools")
    public static let fileURL = directory.appending(path: "cmd-tab.json5")

    public private(set) var config = Config()
    public private(set) var error: String?
    public private(set) var warnings: [String] = []
    public private(set) var fileIsBroken = false
    @ObservationIgnored public var onChange: ((Config) -> Void)?

    @ObservationIgnored private var directorySource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    /// The file as last read or written, so a save can tell that someone else has changed it since.
    @ObservationIgnored private var knownContents: Data?
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let file: URL

    /// `directory` is for tests. The host and the tools use the one under ~/.config.
    public init(persists: Bool = true, directory: URL = ConfigStore.directory) {
        self.persists = persists
        self.directory = directory
        file = directory.appending(path: Self.fileURL.lastPathComponent)
    }

    public func start() {
        reload()
    }

    public func update(_ edit: (inout Config) -> Void) {
        guard !fileIsBroken else { return }
        var next = config
        edit(&next)
        guard next != config else { return }
        config = next
        onChange?(next)
        scheduleSave()
    }

    /// Also replaces a file that does not parse, since the user asked for defaults.
    public func resetToDefaults() {
        fileIsBroken = false
        error = nil
        warnings = []
        if config != Config() {
            config = Config()
            onChange?(config)
        }
        guard persists else { return }
        save(replacingFile: true)
    }

    public func flush() {
        guard saveWork != nil else { return }
        save()
    }

    public func load() {
        // Edits still waiting to be saved are newer than the file as last read. If it has changed since, the
        // save loads it instead.
        guard saveWork == nil else { return }
        // A deleted file comes back with the defaults, as on first launch.
        createDefaultFileIfMissing()
        // Only the host creates the file, so a reader that finds none uses the defaults the host writes.
        let missing = !persists && !FileManager.default.fileExists(atPath: file.path)
        guard let data = missing ? Data(Config.defaultFileContents.utf8) : try? Data(contentsOf: file) else {
            let target = Self.writeTarget(for: file)
            error = target == file
                ? "cannot read \(file.path)"
                : "cannot read \(file.path), a link to \(target.path), which is missing"
            fileIsBroken = true
            return
        }
        if !missing { knownContents = data }
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
    public func openInEditor() {
        flush()
        if NSWorkspace.shared.urlForApplication(toOpen: file) != nil {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.open(
                [file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    public func revealInFinder() {
        flush()
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    public static func revealDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
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

    /// A refused save leaves the file as it was, which still parses, so the file is not marked broken. A file
    /// changed since it was last read or written holds an edit newer than the one waiting here, so it is loaded
    /// instead, unless the user asked to replace it.
    private func save(replacingFile: Bool = false) {
        saveWork?.cancel()
        saveWork = nil
        guard replacingFile || (try? Data(contentsOf: file)) == knownContents else {
            Diagnostics.log.notice("config: the file changed before Settings saved an edit, so the file wins")
            return load()
        }
        let contents: String
        do {
            contents = try config.checkedFileContents()
        } catch {
            self.error = "These settings would not read back, so the file was left as it was: \(error.description)"
            Diagnostics.log.error("config save refused: \(error.description, privacy: .public)")
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data(contents.utf8)
            try data.write(to: Self.writeTarget(for: file), options: .atomic)
            knownContents = data
        } catch {
            self.error = "The file could not be written: \(error.localizedDescription)"
            Diagnostics.log.error("config save: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Not over a link to a file that is missing, such as a dotfiles checkout that is not there yet.
    private func createDefaultFileIfMissing() {
        let manager = FileManager.default
        guard persists, !manager.fileExists(atPath: file.path), Self.writeTarget(for: file) == file else { return }
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Config.defaultFileContents.write(to: file, atomically: true, encoding: .utf8)
    }

    /// A dotfiles setup often links the file, and an atomic write replaces a link with a plain file, so saves
    /// go to the file at the end of the links, even one that does not exist yet.
    public static func writeTarget(for url: URL) -> URL {
        var target = url
        // Links can form a loop.
        for _ in 0..<32 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path) else { break }
            target = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : target.deletingLastPathComponent().appending(path: destination)
            target = target.standardizedFileURL
        }
        return target
    }

    /// Opens the watches before loading, so no change after the load goes unseen. The host's load recreates
    /// a missing directory and file, which the watches before it could not open. Only the host creates them,
    /// so a tool keeps trying while the directory is gone.
    private func reload() {
        rewatch()
        load()
        guard directorySource == nil || fileSource == nil else { return }
        rewatch()
        if directorySource == nil { scheduleReload(after: 1000) }
    }

    /// Editors often save by replacing the file, and the directory itself can be replaced, as when a dotfiles
    /// setup links it again, so both are watched and both watches opened again after every change.
    private func rewatch() {
        directorySource?.cancel()
        directorySource = watch(directory.path, events: [.write, .delete, .rename])
        fileSource?.cancel()
        fileSource = watch(file.path, events: [.write, .extend, .delete, .rename, .attrib])
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

    private func scheduleReload(after milliseconds: Int = 100) {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: work)
    }
}
