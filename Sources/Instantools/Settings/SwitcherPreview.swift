import AppKit
import AppSwitcherCore
import AppSwitcherKit
import SwiftUI

struct PreviewApp: Identifiable {
    let id: Int32
    let name: String
    let icon: NSImage
    let bundleId: String?
}

struct SwitcherPreview: View {
    let apps: [PreviewApp]
    let iconSize: Double
    /// The status while Cmd+Tab is not active, which also dims the panel.
    let badge: String?
    let appKeys: [Config.AppKey]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let tile = PanelStyle.tileSize(iconSize: CGFloat(iconSize))
            let inset = PanelStyle.tileInset(tile: tile)
            let panelWidth = 2 * PanelStyle.padding + CGFloat(max(apps.count, 1)) * tile
            let panelHeight = 2 * PanelStyle.padding + tile + PanelStyle.nameHeight
            let scale = max(0.1, min(1, (geometry.size.width - 40) / panelWidth, (geometry.size.height - 16) / panelHeight))
            ZStack {
                // No apps while the Cmd+Tab tool is off.
                if !apps.isEmpty {
                    panel(tile: tile, inset: inset)
                        .frame(width: panelWidth, height: panelHeight)
                        .scaleEffect(scale)
                        // scaleEffect does not change layout size, so reserve the scaled size explicitly.
                        .frame(width: panelWidth * scale, height: panelHeight * scale)
                        .opacity(badge == nil ? 1 : 0.35)
                        .saturation(badge == nil ? 1 : 0)
                }
                if let badge {
                    Text(badge)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func panel(tile: CGFloat, inset: CGFloat) -> some View {
        let dark = colorScheme == .dark
        let selected = apps.count > 1 ? 1 : 0
        let keys = AppKeyMap(appKeys)
        let icon = tile - 2 * inset
        let badge = PanelStyle.badgeSize(icon: icon)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: icon, height: icon)
                        .overlay(alignment: .bottomTrailing) {
                            if let key = keys.key(for: app.bundleId), let image = PanelStyle.badgeImage(key) {
                                Image(decorative: image, scale: 1)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: badge, height: badge)
                            }
                        }
                        .padding(inset)
                        .background {
                            if index == selected {
                                RoundedRectangle(cornerRadius: PanelStyle.highlightCornerRadius, style: .continuous)
                                    .fill(Color(PanelStyle.highlight(dark: dark)))
                            }
                        }
                }
            }
            let rowWidth = CGFloat(apps.count) * tile
            let app = apps[selected]
            let name = PanelStyle.nameText(name: app.name, dark: dark)
            let label = NameLabel.span(
                textWidth: PanelStyle.width(of: name), maxWidth: PanelStyle.nameMaxWidth(tile: tile),
                centeredOn: (CGFloat(selected) + 0.5) * tile, within: 0...rowWidth
            )
            Text(app.name)
                .foregroundStyle(dark ? Color.white : .black)
                .font(Font(PanelStyle.nameFont))
                .lineLimit(1)
                .frame(width: label.width, height: PanelStyle.nameLabelHeight)
                .offset(x: label.x + label.width / 2 - rowWidth / 2)
                .frame(width: rowWidth)
                .padding(.top, PanelStyle.nameGap)
        }
        .padding(PanelStyle.padding)
        .background(
            RoundedRectangle(cornerRadius: PanelStyle.cornerRadius, style: .continuous)
                .fill(Color(PanelStyle.background(dark: dark)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color(PanelStyle.border(dark: dark)), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }
}

private extension Color {
    init(_ shade: PanelStyle.Shade) {
        self.init(white: shade.white, opacity: shade.alpha)
    }
}

struct LatencyBars: View {
    let samples: [UInt64]
    let frameMilliseconds: Double

    var body: some View {
        Canvas { context, size in
            let values = samples.suffix(40).map { Double($0) / 1_000_000 }
            let top = max(frameMilliseconds * 2.2, values.max() ?? 0)
            let slot = size.width / 40
            let first = 40 - values.count
            for (index, value) in values.enumerated() {
                let height = max(2, size.height * value / top)
                let rect = CGRect(x: CGFloat(first + index) * slot + 1, y: size.height - height, width: slot - 2, height: height)
                let color: Color = value <= frameMilliseconds ? .green : value <= frameMilliseconds * 2 ? .yellow : .orange
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color.opacity(0.85)))
            }
            let frameY = size.height - size.height * frameMilliseconds / top
            var line = Path()
            line.move(to: CGPoint(x: 0, y: frameY))
            line.addLine(to: CGPoint(x: size.width, y: frameY))
            context.stroke(line, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .accessibilityLabel("Recent draw times")
    }
}
