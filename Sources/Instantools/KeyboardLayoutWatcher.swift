import AppKit
import Carbon
import InstantoolsKit

/// A keyboard layout as Settings and the menu show it.
struct KeyboardLayout: Equatable, Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    /// Such as "EN", for a layout without an icon.
    let badge: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

/// The host's own view of the keyboard layouts, so Settings and the menu show them live even while Language is
/// off, and a layout picked there is selected here rather than through the tool.
@MainActor
final class KeyboardLayoutWatcher: NSObject {
    private(set) var layouts: [KeyboardLayout] = []
    private(set) var currentId: String?
    var onChange: (() -> Void)?
    private var sources: [KeyboardLayouts.Layout] = []
    private var menuIcons: [String: NSImage] = [:]

    func start() {
        reload()
        KeyboardLayouts.observeChanges(self, enabled: #selector(enabledChanged), selected: #selector(selectedChanged))
    }

    func select(_ id: String) {
        guard let source = sources.first(where: { $0.id == id })?.source else { return }
        let status = KeyboardLayouts.select(source)
        if status != noErr { Diagnostics.log.error("switch to \(id, privacy: .public) from the host failed: \(status)") }
        updateCurrent()
    }

    func updateCurrent() {
        let id = KeyboardLayouts.currentId()
        guard id != currentId else { return }
        currentId = id
        onChange?()
    }

    /// A menu shows an image at its own size, so each is drawn at 16 points once.
    func menuIcon(for id: String) -> NSImage? {
        menuIcons[id]
    }

    @objc private func enabledChanged() {
        reload()
        onChange?()
    }

    @objc private func selectedChanged() {
        updateCurrent()
    }

    private func reload() {
        sources = KeyboardLayouts.enabled()
        layouts = sources.map { source in
            KeyboardLayout(
                id: source.id, name: source.name, icon: source.iconURL.flatMap(NSImage.init(contentsOf:)),
                badge: source.language?.split(separator: "-").first.map { $0.uppercased() }
            )
        }
        let icons = layouts.compactMap { layout in
            layout.icon.map { icon in
                (layout.id, NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    NSGraphicsContext.current?.imageInterpolation = .high
                    icon.draw(in: rect)
                    return true
                })
            }
        }
        menuIcons = Dictionary(icons) { first, _ in first }
        currentId = KeyboardLayouts.currentId()
    }
}
