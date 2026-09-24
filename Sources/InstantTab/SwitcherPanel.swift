import AppKit
import InstantTabCore

/// Created once and reused: showing it only sets layer frames and contents. No SwiftUI, blur or animation.
@MainActor
final class SwitcherPanel {
    private enum Metrics {
        static let padding: CGFloat = 14
        static let tileInset: CGFloat = 10
        static let nameHeight: CGFloat = 26
        static let screenMargin: CGFloat = 40
    }

    private let icons: IconCache
    private let panel: NSPanel
    private let mouseView = MouseView()
    private let root = CALayer()
    private let background = CALayer()
    private let highlight = CALayer()
    private let nameLayer = CATextLayer()
    private var tiles: [CALayer] = []
    private var tileSize: CGFloat = 0
    private var tileInset: CGFloat = 0
    private var panelWidth: CGFloat = 0
    private var entries: [SwitcherEntry] = []
    private var isVisible = false
    private var pressedIndex: Int?

    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var view: NSView { mouseView }

    init(icons: IconCache) {
        self.icons = icons
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        // Hiding InstantTab from its own switcher must not hide the switcher.
        panel.canHide = false

        mouseView.layer = root
        mouseView.wantsLayer = true
        mouseView.onMouse = { [weak self] type, point in self?.handleMouse(type, at: point) }
        panel.contentView = mouseView

        background.cornerRadius = 22
        background.cornerCurve = .continuous
        highlight.cornerRadius = 14
        highlight.cornerCurve = .continuous
        nameLayer.alignmentMode = .center
        nameLayer.truncationMode = .end
        nameLayer.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLayer.fontSize = 13
        root.addSublayer(background)
        root.addSublayer(highlight)
        root.addSublayer(nameLayer)
    }

    /// Orders the panel in once, invisibly, so the first real show skips backing store setup.
    func warmUp(entries: [SwitcherEntry], on screen: NSScreen?, iconSize: CGFloat) {
        guard let screen, !entries.isEmpty else { return }
        panel.alphaValue = 0
        layout(entries: entries, selected: 0, on: screen, iconSize: iconSize)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func show(entries: [SwitcherEntry], selected: Int, on screen: NSScreen, iconSize: CGFloat) {
        layout(entries: entries, selected: selected, on: screen, iconSize: iconSize)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func update(entries: [SwitcherEntry], selected: Int, on screen: NSScreen, iconSize: CGFloat) {
        guard isVisible else { return }
        layout(entries: entries, selected: selected, on: screen, iconSize: iconSize)
    }

    func select(_ index: Int) {
        guard isVisible, entries.indices.contains(index) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeSelection(index)
        CATransaction.commit()
    }

    func hide() {
        guard isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
        pressedIndex = nil
    }

    /// Only real pointer movement selects, so a panel opening under a resting pointer keeps its selection.
    private func handleMouse(_ type: NSEvent.EventType, at point: CGPoint) {
        guard isVisible else { return }
        let index = index(at: point)
        switch type {
        case .mouseMoved:
            if let index { onHover?(index) }
        case .leftMouseDown:
            pressedIndex = index
            if let index { onHover?(index) }
        case .leftMouseUp:
            defer { pressedIndex = nil }
            if let index, index == pressedIndex { onClick?(index) }
        default:
            break
        }
    }

    private func index(at point: CGPoint) -> Int? {
        let row = CGRect(x: Metrics.padding, y: Metrics.padding + Metrics.nameHeight, width: CGFloat(entries.count) * tileSize, height: tileSize)
        guard tileSize > 0, row.contains(point) else { return nil }
        let index = Int((point.x - Metrics.padding) / tileSize)
        return entries.indices.contains(index) ? index : nil
    }

    private func layout(entries: [SwitcherEntry], selected: Int, on screen: NSScreen, iconSize: CGFloat) {
        self.entries = entries
        let count = CGFloat(entries.count)
        let available = screen.visibleFrame.width - 2 * Metrics.screenMargin - 2 * Metrics.padding
        tileSize = min(iconSize + 2 * Metrics.tileInset, available / count).rounded(.down)
        tileInset = min(Metrics.tileInset, (tileSize * 0.1).rounded(.down))
        let icon = tileSize - 2 * tileInset

        let size = CGSize(
            width: 2 * Metrics.padding + count * tileSize,
            height: 2 * Metrics.padding + tileSize + Metrics.nameHeight
        )
        let origin = CGPoint(x: (screen.frame.midX - size.width / 2).rounded(), y: (screen.frame.midY - size.height / 2).rounded())
        let sizeChanged = panel.frame.size != size
        panelWidth = size.width
        panel.setFrame(CGRect(origin: origin, size: size), display: false)

        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let scale = screen.backingScaleFactor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.contentsScale = scale
        background.frame = CGRect(origin: .zero, size: size)
        background.backgroundColor = (dark ? NSColor(white: 0.14, alpha: 0.9) : NSColor(white: 0.96, alpha: 0.9)).cgColor
        background.borderWidth = 1 / scale
        background.borderColor = (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.1)).cgColor
        highlight.backgroundColor = (dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.1)).cgColor
        nameLayer.foregroundColor = (dark ? NSColor.white : NSColor.black).cgColor
        nameLayer.contentsScale = scale

        while tiles.count < entries.count {
            let tile = CALayer()
            tile.contentsGravity = .resizeAspect
            tile.minificationFilter = .trilinear
            root.insertSublayer(tile, above: highlight)
            tiles.append(tile)
        }
        for (index, tile) in tiles.enumerated() {
            guard index < entries.count else {
                tile.isHidden = true
                continue
            }
            tile.isHidden = false
            tile.contents = icons.icon(for: entries[index].pid)
            tile.contentsScale = scale
            tile.frame = CGRect(
                x: Metrics.padding + CGFloat(index) * tileSize + tileInset,
                y: Metrics.padding + Metrics.nameHeight + tileInset,
                width: icon, height: icon
            )
        }
        placeSelection(selected)
        CATransaction.commit()
        if sizeChanged { panel.invalidateShadow() }
    }

    private func placeSelection(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        let x = Metrics.padding + CGFloat(index) * tileSize
        highlight.frame = CGRect(x: x, y: Metrics.padding + Metrics.nameHeight, width: tileSize, height: tileSize)
        let nameWidth = min(panelWidth - 2 * Metrics.padding, max(tileSize * 2.5, 160))
        let nameX = min(max(x + tileSize / 2 - nameWidth / 2, Metrics.padding), panelWidth - Metrics.padding - nameWidth)
        nameLayer.frame = CGRect(x: nameX, y: Metrics.padding, width: nameWidth, height: Metrics.nameHeight - 6)
        nameLayer.string = entries[index].name
    }
}

private final class MouseView: NSView {
    var onMouse: ((NSEvent.EventType, CGPoint) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) { forward(event) }
    override func mouseDown(with event: NSEvent) { forward(event) }
    override func mouseUp(with event: NSEvent) { forward(event) }

    private func forward(_ event: NSEvent) {
        onMouse?(event.type, convert(event.locationInWindow, from: nil))
    }
}
