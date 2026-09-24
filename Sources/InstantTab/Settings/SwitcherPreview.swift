import AppKit
import SwiftUI

struct PreviewApp: Identifiable {
    let id: Int32
    let name: String
    let icon: NSImage
}

struct SwitcherPreview: View {
    let apps: [PreviewApp]
    let iconSize: Double
    let isActive: Bool
    @Environment(\.colorScheme) private var colorScheme

    // SwitcherPanel.Metrics
    private let padding: CGFloat = 14
    private let inset: CGFloat = 10
    private let nameHeight: CGFloat = 26

    var bottomInset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let shown = apps
            let tile = CGFloat(iconSize) + 2 * inset
            let panelWidth = 2 * padding + CGFloat(max(shown.count, 1)) * tile
            let panelHeight = 2 * padding + tile + nameHeight
            let area = CGSize(width: geometry.size.width, height: geometry.size.height - bottomInset)
            let scale = max(0.1, min(1, (area.width - 40) / panelWidth, (area.height - 36) / panelHeight))
            ZStack {
                panel(shown, tile: tile)
                    .frame(width: panelWidth, height: panelHeight)
                    .scaleEffect(scale)
                    // scaleEffect does not change layout size, so reserve the scaled size explicitly.
                    .frame(width: panelWidth * scale, height: panelHeight * scale)
                    .opacity(isActive ? 1 : 0.35)
                    .saturation(isActive ? 1 : 0)
                if !isActive {
                    Label("Paused", systemImage: "pause.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .frame(width: area.width, height: area.height)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(Wallpaper())
        .clipShape(Hero.shape)
    }

    private func panel(_ shown: [PreviewApp], tile: CGFloat) -> some View {
        let dark = colorScheme == .dark
        let selected = shown.count > 1 ? 1 : 0
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, app in
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: CGFloat(iconSize), height: CGFloat(iconSize))
                        .padding(inset)
                        .background {
                            if index == selected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1))
                            }
                        }
                }
            }
            let rowWidth = CGFloat(shown.count) * tile
            Text(shown.indices.contains(selected) ? shown[selected].name : "")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(dark ? .white : .black)
                .lineLimit(1)
                .frame(width: max(tile * 2.5, 160), height: nameHeight - 6)
                .offset(x: (CGFloat(selected) + 0.5) * tile - rowWidth / 2)
                .frame(width: rowWidth)
                .padding(.top, 3)
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(dark ? Color(white: 0.14, opacity: 0.9) : Color(white: 0.96, opacity: 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
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
