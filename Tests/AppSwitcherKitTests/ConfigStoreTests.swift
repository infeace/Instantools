import AppSwitcherCore
import Foundation
import Testing
@testable import AppSwitcherKit

/// Against real directories, since these failures are in how the file system and its events behave.
@MainActor
struct ConfigStoreTests {
    private let files = FileManager.default

    private func makeRoot() throws -> URL {
        let root = files.temporaryDirectory.appending(path: "ConfigStoreTests-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func isLink(_ url: URL) -> Bool {
        (try? files.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Watch events and reloads arrive on the main queue, which runs while this waits.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test func savingKeepsALinkedFileLinked() throws {
        let root = try makeRoot()
        defer { try? files.removeItem(at: root) }
        let dotfiles = root.appending(path: "dotfiles")
        let config = root.appending(path: "config")
        try files.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try files.createDirectory(at: config, withIntermediateDirectories: true)
        let target = dotfiles.appending(path: "cmd-tab.json5")
        let link = config.appending(path: "cmd-tab.json5")
        try write("{ showDelayMs: 100 }", to: target)
        try files.createSymbolicLink(atPath: link.path, withDestinationPath: "../dotfiles/cmd-tab.json5")

        let store = ConfigStore(directory: config)
        store.start()
        #expect(store.config.showDelayMs == 100)
        store.update { $0.showDelayMs = 200 }
        store.flush()

        #expect(isLink(link))
        #expect(try Config.parse(Data(contentsOf: target)).config.showDelayMs == 200)
    }

    @Test func aLinkToAMissingFileIsNotReplacedWithDefaults() throws {
        let root = try makeRoot()
        defer { try? files.removeItem(at: root) }
        let config = root.appending(path: "config")
        try files.createDirectory(at: config, withIntermediateDirectories: true)
        let link = config.appending(path: "cmd-tab.json5")
        try files.createSymbolicLink(atPath: link.path, withDestinationPath: root.appending(path: "dotfiles/cmd-tab.json5").path)

        let store = ConfigStore(directory: config)
        store.start()

        #expect(isLink(link))
        #expect(store.fileIsBroken)
        #expect(store.error?.contains("which is missing") == true)
    }

    /// As the Cmd+Tab tool reads it: it never creates the directory, so it has to find the new one.
    @Test func aReplacedDirectoryIsFollowed() async throws {
        let root = try makeRoot()
        defer { try? files.removeItem(at: root) }
        let config = root.appending(path: "config")
        try files.createDirectory(at: config, withIntermediateDirectories: true)
        try write("{ showDelayMs: 100 }", to: config.appending(path: "cmd-tab.json5"))

        let store = ConfigStore(persists: false, directory: config)
        store.start()
        #expect(store.config.showDelayMs == 100)

        try files.moveItem(at: config, to: root.appending(path: "config-old"))
        try files.createDirectory(at: config, withIntermediateDirectories: true)
        try write("{ showDelayMs: 200 }", to: config.appending(path: "cmd-tab.json5"))
        #expect(try await eventually { store.config.showDelayMs == 200 })

        try write("{ showDelayMs: 300 }", to: config.appending(path: "cmd-tab.json5"))
        #expect(try await eventually { store.config.showDelayMs == 300 })
    }

    /// As the host keeps it: the directory comes back with the defaults, and edits after that are followed.
    @Test func aDeletedDirectoryComesBackAndIsFollowed() async throws {
        let root = try makeRoot()
        defer { try? files.removeItem(at: root) }
        let config = root.appending(path: "config")
        let file = config.appending(path: "cmd-tab.json5")

        let store = ConfigStore(directory: config)
        store.start()
        #expect(files.fileExists(atPath: file.path))

        try files.removeItem(at: config)
        #expect(try await eventually { files.fileExists(atPath: file.path) })

        try write("{ showDelayMs: 250 }", to: file)
        #expect(try await eventually { store.config.showDelayMs == 250 })
    }
}
