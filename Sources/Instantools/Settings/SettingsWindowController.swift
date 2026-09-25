import AppKit
import SwiftUI

/// The window and its model exist only while open. Meanwhile Instantools is a regular app so Cmd+Tab reaches it.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let makeModel: () -> SettingsModel
    private var window: NSWindow?
    private var model: SettingsModel?

    var isOpen: Bool { window != nil }

    init(makeModel: @escaping () -> SettingsModel) {
        self.makeModel = makeModel
    }

    func show() {
        if window == nil {
            let model = makeModel()
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Instantools Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 860, height: 640))
            window.contentMinSize = NSSize(width: 720, height: 480)
            window.setFrameAutosaveName("InstantoolsSettings")
            window.delegate = self
            if !window.setFrameUsingName("InstantoolsSettings") { window.center() }
            model.start()
            self.window = window
            self.model = model
            OwnWindow.opened(window)
        }
        if let window { OwnWindow.present(window) }
    }

    /// For tool state changes and status replies, which arrive between the model's own refreshes.
    func refresh() {
        model?.refresh()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model?.refreshSystemState()
    }

    /// Nothing refreshes while the window is minimized, hidden or covered.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window, let model else { return }
        if window.occlusionState.contains(.visible) { model.start() } else { model.stop() }
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        model?.configStore.flush()
        model = nil
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let window = self?.window else { return }
                self?.window = nil
                OwnWindow.closed(window)
            }
        }
    }
}
