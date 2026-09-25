import AppKit
import SwiftUI

/// Shown once, on a first launch that carried nothing over from the standalone apps. Like Settings, the window
/// and its model exist only while open, and Instantools is a regular app meanwhile.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 640, height: 560)

    private let makeModel: () -> WelcomeModel
    private var window: NSWindow?
    private var model: WelcomeModel?

    var isOpen: Bool { window != nil }

    init(makeModel: @escaping () -> WelcomeModel) {
        self.makeModel = makeModel
    }

    func show() {
        if window == nil {
            let model = makeModel()
            let window = Self.makeWindow(model: model)
            window.delegate = self
            model.close = { [weak window] in window?.close() }
            self.window = window
            self.model = model
            OwnWindow.opened(window)
        }
        if let window { OwnWindow.present(window) }
    }

    /// Also used for snapshots.
    static func makeWindow(model: WelcomeModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.title = "Welcome to Instantools"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: WelcomeView(model: model))
        // The window keeps its fixed size rather than fitting the steps, which differ in height.
        content.sizingOptions = []
        window.contentView = content
        window.center()
        return window
    }

    /// Back from System Settings, where a permission may have just been allowed.
    func windowDidBecomeKey(_ notification: Notification) {
        model?.checkPermissions()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        model?.isVisible = window.occlusionState.contains(.visible)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
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
