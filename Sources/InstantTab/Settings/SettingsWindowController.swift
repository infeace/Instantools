import AppKit
import SwiftUI

/// Creates the Settings window on open and releases it on close, so it costs nothing otherwise.
/// While it is open InstantTab is a regular app, so the window can be reached with Cmd+Tab.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let makeModel: () -> SettingsModel
    private let onOpenChange: (Bool) -> Void
    private var window: NSWindow?
    private var model: SettingsModel?

    var isOpen: Bool { window != nil }

    init(makeModel: @escaping () -> SettingsModel, onOpenChange: @escaping (Bool) -> Void) {
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
            window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 860, height: 640))
            window.contentMinSize = NSSize(width: 720, height: 480)
            window.setFrameAutosaveName("InstantTabSettings")
            window.delegate = self
            if !window.setFrameUsingName("InstantTabSettings") { window.center() }
            model.start()
            self.window = window
            self.model = model
            NSApp.setActivationPolicy(.regular)
            onOpenChange(true)
        }
        guard let window else { return }
        OwnWindow.bringForward(window)
        // Right after becoming a regular app the first request can be dropped, so repeat it once.
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
        // Release the window after AppKit finishes closing it.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.window = nil
                NSApp.setActivationPolicy(.accessory)
                self?.onOpenChange(false)
            }
        }
    }
}
