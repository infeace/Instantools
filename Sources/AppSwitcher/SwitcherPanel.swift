import AppKit
import AppSwitcherCore
import AppSwitcherKit

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
    private var badges: [CALayer] = []
    private var tileSize: CGFloat = 0
    private var tileInset: CGFloat = 0
    private var panelWidth: CGFloat = 0
    private var entries: [SwitcherEntry] = []
    private var isVisible = false
    private var selectedIndex = 0
    /// A pid, since the list can change between mouse-down and mouse-up.
    private var pressedPid: Int32?
    /// Built and measured once per name and state, since the selection moves on every Tab. The colors are
    /// part of the text, so it is rebuilt when the appearance changes.
    private var nameTexts: [String: (text: NSAttributedString, width: CGFloat)] = [:]
    private var isDark = false

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

    /// Called when the config changes, so a show only swaps layer contents.
    func prepareBadges(for keys: [Character]) {
        for key in keys { _ = PanelStyle.badgeImage(key) }
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
        pressedPid = nil
    }

    /// Only real pointer movement selects, so a panel opening under a resting pointer keeps its selection.
    private func handleMouse(_ type: NSEvent.EventType, at point: CGPoint) {
        guard isVisible else { return }
        let index = index(at: point)
        switch type {
        case .mouseMoved:
            if let index, index != selectedIndex { onHover?(index) }
        case .leftMouseDown:
            pressedPid = index.map { entries[$0].pid }
            if let index { onHover?(index) }
        case .leftMouseUp:
            defer { pressedPid = nil }
            if let index, entries[index].pid == pressedPid { onClick?(index) }
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
        nameLayer.contentsScale = scale
        if dark != isDark {
            isDark = dark
            nameTexts = [:]
        }

        while tiles.count < entries.count {
            let tile = CALayer()
            tile.contentsGravity = .resizeAspect
            tile.minificationFilter = .trilinear
            root.insertSublayer(tile, above: highlight)
            tiles.append(tile)
            let badge = CALayer()
            badge.minificationFilter = .trilinear
            root.addSublayer(badge)
            badges.append(badge)
        }
        let badgeSize = PanelStyle.badgeSize(icon: icon)
        for (index, tile) in tiles.enumerated() {
            let badge = badges[index]
            guard index < entries.count else {
                tile.isHidden = true
                badge.isHidden = true
                continue
            }
            tile.isHidden = false
            tile.contents = icons.icon(for: entries[index].pid)
            tile.contentsScale = scale
            tile.opacity = entries[index].state == nil ? 1 : Self.dimmedOpacity
            tile.frame = CGRect(
                x: Metrics.padding + CGFloat(index) * tileSize + tileInset,
                y: Metrics.padding + Metrics.nameHeight + tileInset,
                width: icon, height: icon
            )
            let image = entries[index].key.flatMap(PanelStyle.badgeImage)
            badge.isHidden = image == nil
            badge.contents = image
            // The icon's bottom-right corner, clear of where the Dock puts unread badges.
            badge.frame = CGRect(x: tile.frame.maxX - badgeSize, y: tile.frame.minY, width: badgeSize, height: badgeSize)
        }
        placeSelection(selected)
        CATransaction.commit()
        if sizeChanged { panel.invalidateShadow() }
    }

    private func placeSelection(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedIndex = index
        let x = Metrics.padding + CGFloat(index) * tileSize
        highlight.frame = CGRect(x: x, y: Metrics.padding + Metrics.nameHeight, width: tileSize, height: tileSize)
        let name = nameText(for: entries[index])
        let label = NameLabel.span(
            textWidth: name.width, maxWidth: max(tileSize * 2.5, 160),
            centeredOn: x + tileSize / 2, within: Metrics.padding...(panelWidth - Metrics.padding)
        )
        nameLayer.frame = CGRect(x: label.x, y: Metrics.padding, width: label.width, height: Metrics.nameHeight - 6)
        nameLayer.string = name.text
    }

    private func nameText(for entry: SwitcherEntry) -> (text: NSAttributedString, width: CGFloat) {
        let key = entry.state.map { "\(entry.name)\u{0}\($0)" } ?? entry.name
        if let cached = nameTexts[key] { return cached }
        let text = PanelStyle.nameText(name: entry.name, state: entry.state, dark: isDark)
        let result = (text, PanelStyle.width(of: text))
        nameTexts[key] = result
        return result
    }

    static let dimmedOpacity = PanelStyle.dimmedOpacity
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
