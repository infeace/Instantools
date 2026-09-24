import AppKit
import SwiftUI

/// Created on open and released on close. While open, InstantTab is a regular app so Cmd+Tab reaches it.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let makeModel: () -> SettingsModel
    private let onOpenChange: () -> Void
    private var window: NSWindow?
    private var model: SettingsModel?

    var isOpen: Bool { window != nil }

    init(makeModel: @escaping () -> SettingsModel, onOpenChange: @escaping () -> Void) {
        self.makeModel = makeModel
        self.onOpenChange = onOpenChange
    }

    func show() {
        if window == nil {
            let model = makeModel()
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "InstantTab Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 860, height: 640))
            window.contentMinSize = NSSize(width: 720, height: 480)
            window.setFrameAutosaveName("InstantTabSettings")
            window.delegate = self
            if !window.setFrameUsingName("InstantTabSettings") { window.center() }
            model.start()
            self.window = window
            self.model = model
            NSApp.setActivationPolicy(.regular)
            onOpenChange()
        }
        guard let window else { return }
        OwnWindow.bringForward(window)
        // Right after becoming a regular app the first request can be dropped.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if !NSApp.isActive || !window.isKeyWindow { OwnWindow.bringForward(window) }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        model?.configStore.flush()
        model = nil
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.window = nil
                NSApp.setActivationPolicy(.accessory)
                self?.onOpenChange()
            }
        }
    }
}
