import AppKit
import AppSwitcherKit
import UniformTypeIdentifiers

@MainActor
final class IconCache {
    /// Sharp up to 128pt on a Retina display. Larger icon sizes switch to 512 pixels, which costs four
    /// times the memory, so the step happens only when the setting crosses 128pt.
    private var pixels = 256
    private var icons: [Int32: CGImage] = [:]
    /// Apps whose icon was not available yet. They get the placeholder without a lookup on the key press
    /// and are retried on the next sync.
    private var missing: Set<Int32> = []
    private var placeholder: CGImage?

    init() {
        placeholder = render(NSWorkspace.shared.icon(for: .applicationBundle))
    }

    func icon(for pid: Int32) -> CGImage? {
        if let icon = icons[pid] { return icon }
        if missing.contains(pid) { return placeholder }
        return load(pid)
    }

    func sync(with pids: [Int32]) {
        let live = Set(pids)
        icons = icons.filter { live.contains($0.key) }
        missing = missing.intersection(live)
        for pid in pids where icons[pid] == nil {
            _ = load(pid)
        }
    }

    func setIconSize(_ points: Double) {
        let needed = points > 128 ? 512 : 256
        guard needed != pixels else { return }
        pixels = needed
        let pids = Array(icons.keys) + missing
        icons = [:]
        missing = []
        placeholder = render(NSWorkspace.shared.icon(for: .applicationBundle))
        sync(with: pids)
    }

    private func load(_ pid: Int32) -> CGImage? {
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon, let icon = render(image) else {
            missing.insert(pid)
            return placeholder
        }
        missing.remove(pid)
        icons[pid] = icon
        return icon
    }

    private func render(_ image: NSImage) -> CGImage? {
        PanelStyle.renderImage(pixels: pixels) {
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        }
    }
}
